# syntax=docker/dockerfile:1
FROM node:24-bookworm AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends musl-tools \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ARG CI=true
ARG ELECTRON_SKIP_BINARY_DOWNLOAD=1
ARG PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
ARG DSH_TELEMETRY_DISABLED=1
ARG DSH_GATE_CONCURRENCY=2
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN npm install --global "$(node -p 'require("./package.json").packageManager')"
COPY . .
RUN --mount=type=cache,id=dsh-pnpm,target=/pnpm/store \
    pnpm install --frozen-lockfile --store-dir /pnpm/store

ARG DSH_CLIENT_COMMIT_HASH
RUN pnpm run build:artifacts \
    && pnpm --dir native/system run build:native

FROM build AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash bubblewrap ca-certificates curl git openssh-client python3 ripgrep tini \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /data /workspace
ENV NODE_ENV=production \
    DSH_HOME=/data \
    DSH_AGENTS_HOME=/data/agents \
    DSH_WEB_PORT=3080 \
    DSH_WEB_PUBLIC_URL=http://localhost:3080/ \
    DSH_TELEMETRY_DISABLED=1
COPY docker/config.mjs docker/entrypoint.mjs /opt/dsh/
WORKDIR /workspace
EXPOSE 3080
VOLUME ["/data", "/workspace"]
ENTRYPOINT ["/usr/bin/tini", "--", "node", "/opt/dsh/entrypoint.mjs"]
