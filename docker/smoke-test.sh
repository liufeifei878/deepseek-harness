#!/usr/bin/env bash
# Exercise the published image without model credentials. Requires Docker, curl and Python 3.
set +x
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: bash docker/smoke-test.sh IMAGE\n' >&2
  exit 2
fi
for command in docker curl python3; do
  command -v "$command" >/dev/null || { printf 'Missing command: %s\n' "$command" >&2; exit 2; }
done

umask 077
scratch=$(mktemp -d "${TMPDIR:-/tmp}/dsh-docker-smoke.XXXXXXXXXX")
container="dsh-smoke-${scratch##*.}"
volume=''
container_created=false

cleanup() {
  local status=$?
  trap - EXIT
  set +e
  if [[ $status -ne 0 && $container_created == true ]]; then
    printf 'Container diagnostics (launch token redacted):\n' >&2
    docker inspect --format 'status={{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}}' "$container" >&2
    docker logs --tail 200 "$container" 2>&1 |
      sed -E 's/([?&]token=)[^[:space:])]+/\1<redacted>/g' >&2
  fi
  if [[ $container_created == true ]]; then
    docker rm --force --volumes "$container" >/dev/null || status=1
  fi
  if [[ -n $volume ]]; then
    docker volume rm "$volume" >/dev/null || status=1
  fi
  rm -rf -- "$scratch"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() { printf 'Docker smoke failed: %s\n' "$*" >&2; exit 1; }

volume=$(docker volume create)
docker create --name "$container" \
  --publish 127.0.0.1::3080 \
  --mount "type=volume,source=$volume,target=/data" \
  --env DSH_TELEMETRY_DISABLED=1 \
  --env DEEPSEEK_API_KEY= \
  "$1" >"$scratch/container-id"
container_created=true
docker start "$container" >/dev/null

wait_ready() {
  local deadline=$((SECONDS + 180)) state health started_at
  started_at=$(docker inspect --format '{{.State.StartedAt}}' "$container")
  while ((SECONDS < deadline)); do
    state=$(docker inspect --format '{{.State.Status}}' "$container")
    [[ $state == running ]] || fail "container stopped before readiness ($state)"
    health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container")
    [[ $health != missing ]] || fail 'image has no health check'
    [[ $health != unhealthy ]] || fail 'container health check failed'
    docker logs --since "$started_at" "$container" >"$scratch/startup.log" 2>&1
    if [[ $health == healthy ]] && python3 - "$scratch/startup.log" "$scratch/token" <<'PY'
import pathlib
import re
import sys
import urllib.parse

logs = pathlib.Path(sys.argv[1]).read_text(errors="replace")
for match in re.finditer(r"dsh web: (http://[^\s]+)", logs):
    url = urllib.parse.urlsplit(match[1])
    token = urllib.parse.parse_qs(url.query).get("token", [])
    if (url.scheme == "http" and url.netloc == "localhost:3080" and url.path == "/"
            and len(token) == 1 and re.fullmatch(r"[A-Za-z0-9_-]{43}", token[0])):
        pathlib.Path(sys.argv[2]).write_text(token[0])
        sys.exit(0)
sys.exit(1)
PY
    then
      binding=$(docker port "$container" 3080/tcp)
      [[ $binding =~ ^127\.0\.0\.1:[0-9]+$ ]] || fail 'expected exactly one loopback port mapping'
      base="http://$binding"
      return
    fi
    sleep 1
  done
  fail 'health and authenticated launch URL did not become ready within 180 seconds'
}

request() {
  local expected=$1 name=$2 path=$3 status
  shift 3
  status=$(curl --silent --show-error --noproxy '*' \
    --connect-timeout 5 --max-time 30 \
    --header 'Host: localhost:3080' \
    --output "$scratch/$name.body" --dump-header "$scratch/$name.headers" \
    --write-out '%{http_code}' "$@" "$base$path")
  [[ $status == "$expected" ]] || fail "$name returned HTTP $status; expected $expected"
}

check_authenticated() {
  request 200 index / --header "@$scratch/cookie"
  python3 - "$scratch/index.body" "$scratch/asset" <<'PY'
import pathlib
import sys
import urllib.parse
from html.parser import HTMLParser

html = pathlib.Path(sys.argv[1]).read_text()
if "__DSH_BOOT__" not in html or "<html" not in html.lower():
    sys.exit("Authenticated response is missing the Web HTML boot payload")

class Assets(HTMLParser):
    paths = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ("src", "href") and value:
                url = urllib.parse.urlsplit(value)
                if not url.scheme and not url.netloc and url.path.startswith(("/assets/", "./assets/", "assets/")):
                    self.paths.append("/" + value.removeprefix("./").lstrip("/"))

assets = Assets()
assets.feed(html)
if not assets.paths:
    sys.exit("Web HTML contains no bundled asset")
pathlib.Path(sys.argv[2]).write_text(assets.paths[0])
PY
  request 200 asset "$(cat "$scratch/asset")" --header "@$scratch/cookie"
  [[ -s "$scratch/asset.body" ]] || fail 'bundled asset is empty'
  request 200 sessions /api/session/list --header "@$scratch/cookie" \
    --header 'Content-Type: application/json' \
    --data '{"type":"client-request","rpcId":"docker-smoke","method":"session/list","payload":{"args":{"_request":{}}}}'
  python3 - "$scratch/sessions.body" <<'PY'
import json
import pathlib
import sys

body = json.loads(pathlib.Path(sys.argv[1]).read_text())
result = body.get("result", {})
if (body.get("type") != "server-response" or body.get("rpcId") != "docker-smoke"
        or result.get("ok") is not True or not isinstance(result.get("value", {}).get("items"), list)):
    sys.exit("Authenticated session/list did not return a successful session list")
PY
}

stop_gracefully() {
  local exit_code
  docker stop --time 30 "$container" >/dev/null
  [[ $(docker inspect --format '{{.State.Running}}' "$container") == false ]] || fail 'container is still running after stop'
  [[ $(docker inspect --format '{{.State.OOMKilled}}' "$container") == false ]] || fail 'container was killed for exceeding memory'
  exit_code=$(docker inspect --format '{{.State.ExitCode}}' "$container")
  case "$exit_code" in
    0|143) ;;
    137) fail 'container required SIGKILL instead of shutting down gracefully' ;;
    *) fail "container shutdown returned exit code $exit_code" ;;
  esac
}

wait_ready
request 401 unauthenticated /
request 303 exchange "/?token=$(cat "$scratch/token")"
python3 - "$scratch/exchange.headers" "$scratch/cookie" <<'PY'
import pathlib
import sys
from email.parser import Parser

raw = pathlib.Path(sys.argv[1]).read_text()
headers = Parser().parsestr(raw.split("\n", 1)[1])
cookie = headers.get("Set-Cookie", "")
if headers.get("Location") != "./" or "httponly" not in cookie.lower() or "samesite=strict" not in cookie.lower():
    sys.exit("Launch token exchange did not produce the expected redirect and browser cookie")
pathlib.Path(sys.argv[2]).write_text("Cookie: " + cookie.split(";", 1)[0] + "\n")
PY
check_authenticated
docker exec "$container" node --input-type=module -e '
  import { writeFileSync } from "node:fs";
  if (process.getuid() === 0) throw new Error("Container runs as root");
  if (process.cwd() !== "/workspace") throw new Error("Unexpected working directory");
  if (process.env.DSH_HOME !== "/data" || process.env.DSH_AGENTS_HOME !== "/data/agents") throw new Error("Unexpected data paths");
  writeFileSync("/data/docker-smoke-probe", "persistent-data\n", { flag: "wx" });
'

cp "$scratch/token" "$scratch/first-token"
stop_gracefully
docker start "$container" >/dev/null
wait_ready
cmp -s "$scratch/first-token" "$scratch/token" && fail 'launch token did not rotate after restart'
docker exec "$container" node --input-type=module -e '
  import { readFileSync } from "node:fs";
  if (readFileSync("/data/docker-smoke-probe", "utf8") !== "persistent-data\n") throw new Error("Data did not survive restart");
'
check_authenticated
stop_gracefully
printf 'Docker smoke passed: Web assets, authentication, non-root storage, restart persistence and graceful shutdown.\n'
