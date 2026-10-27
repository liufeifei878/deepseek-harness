# Docker 部署 Web 版

本 Fork 使用 GitHub Actions 构建 Linux amd64 镜像，并直接推送到 `ghcr.io/liufeifei878/deepseek-harness`。CI 只安装依赖、执行上游 `build:artifacts` 和 Linux native 编译、构建并推送 Docker 镜像，不运行配置测试、`build:check`、smoke 测试或容器启动验证。构建在 GitHub 的 Linux runner 上完成；使用镜像的机器只需要 Docker 和 Compose。

## 启动

在仓库根目录运行：

```sh
docker compose pull
docker compose up -d
docker compose logs deepseek-harness
```

打开日志中 `dsh web:` 后面带 `?token=` 的完整登录链接。默认地址是 `http://localhost:3080/`，仅映射到宿主机回环地址。该链接是登录凭据，请勿公开。模型 API Key 可以在 Web 界面配置，无需放入仓库或 CI secrets。

容器沿用 Node 基础镜像的默认用户 root，不要求把挂载目录的所有者改成 UID 1000。`dsh-data` 保存会话、配置、凭据和共享 skills，`dsh-workspace` 保存工作文件；`docker compose down` 保留这两个卷，`docker compose down -v` 会删除它们。挂载现有工作目录时，用 `./projects:/workspace` 替换工作区卷。

如果 GHCR 提示需要认证，先使用具有 `read:packages` 权限的 GitHub token 登录 `ghcr.io`，或者由仓库所有者在 GitHub 包设置中将包可见性改为 Public。

## 服务器访问

可以保留回环端口，通过 SSH 隧道访问远程主机：

```sh
ssh -L 3080:127.0.0.1:3080 user@your-server
```

需要通过域名访问时，在服务器 Compose 目录的 `.env` 中设置浏览器实际使用的地址：

```dotenv
DSH_WEB_PUBLIC_URL=https://agent.example.com/
```

把 HTTPS 反向代理指向宿主机 `127.0.0.1:3080`，保留 Host 并启用 WebSocket 转发。入口自动将该 URL 的 authority 加入受信列表；其他入口可通过逗号分隔的 `DSH_WEB_TRUSTED_HOSTS` 设置。具体代理要求见[上游公开部署指南](../docs/user/guide/public-deployments.zh.md)。若代理在另一个容器中，需要让其网络能到达服务或调整宿主机端口绑定；`DSH_BIND_ADDRESS` 控制 Compose 绑定地址，`DSH_PORT` 控制宿主机端口。

## 更新与构建

推送到 `master` 会发布 `latest` 和 `sha-<完整提交号>`；推送 `docker-v1.0.0` 这样的 tag 会发布 `docker-v1.0.0`、`1.0.0` 和提交号标签。Actions 页面也支持手动运行。PR 只构建，不发布。

```sh
docker compose pull
docker compose up -d
```

本地自行构建时，需要把 Git 提交号传给前端构建：

```sh
docker build --build-arg DSH_CLIENT_COMMIT_HASH="$(git rev-parse HEAD)" -t deepseek-harness:local .
```

Dockerfile 使用锁文件安装依赖，执行上游 `build:artifacts` 和 Linux native 构建，并通过官方 `dsh` Web 入口启动。运行镜像继承完整构建环境，保留 Node.js、npm、项目指定版本的 pnpm、编译工具以及全部项目依赖、源码和构建产物，供运行时查询和安装插件使用。镜像还包含 bash、Git、Python 3、ripgrep、bubblewrap 和 Landlock 二进制；模型工具的 Linux 沙箱能力仍取决于宿主机内核及容器策略。镜像不包含图形桌面、浏览器二进制或桌面版完整工具环境。

入口自动选择容器的具体 IPv4，因为上游禁止监听 `0.0.0.0`；需要固定绑定地址时可设置 `DSH_WEB_HOST`。遥测上传默认通过 `DSH_TELEMETRY_DISABLED=1` 关闭；上游独立的模型会话日志上传选项仍由 Web 设置控制。
