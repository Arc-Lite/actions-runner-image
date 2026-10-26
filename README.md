# ARC runner image

基于 Ubuntu 26.04，为 Actions Runner Controller (ARC) 准备的 `linux/amd64` runner 镜像。Dockerfile 沿用 `github.com/actions/runner/images/Dockerfile` 的双阶段结构，保留 runner 下载、两套 Kubernetes container hooks、`/home/runner` 工作目录和 UID 1001 的 `runner` 用户。

## 上游脚本与配置

`upstream/runner-images` 是 [github.com/actions/runner-images.git](https://github.com/actions/runner-images.git) 的 Git submodule。安装时直接执行子模块内的脚本，不修改上游文件。

上游脚本、本地构建脚本和工具配置通过 BuildKit `RUN --mount=type=bind` 只读挂载到 `/tmp/runner-image-sources` 下，不复制到镜像层。清理时保留只读挂载点。需要保留的运行时入口脚本和 `/opt/toolset.json` 在安装时显式写入镜像。下载归档、解压目录、APT 索引和 root 用户的工具缓存在产生它们的同一条 `RUN` 中清理；各阶段使用 Bash 的 `set -euo pipefail` 和顺序命令。

`toolsets/toolset.json` 沿用上游的配置结构：`apt`、`toolcache`、`node`、`node_modules`、`java`、`clang`、`dotnet`、`rubygems`、`cmake`、`pwsh`、`pipx` 和 `docker`。Python、Go、Ruby、Node.js 和 CodeQL 预装到 `/opt/hostedtoolcache`，供对应的 setup actions 使用；Python 和 Ruby 使用匹配 Ubuntu 26.04 的包。

| 工具 | 安装方式 |
| --- | --- |
| GCC/G++、系统 Ruby、PHP/Composer、Git/Git LFS、基础开发库与命令 | 上游 Ubuntu APT 安装脚本，包列表来自 JSON；不安装 Fortran 工具链 |
| Node.js 默认 26，npm、n、Yarn | 上游 Ubuntu Slim Node.js 安装脚本；同层清理 n 的版本缓存，保留命令和当前默认 Node.js |
| Python 3.11/3.13/3.14/3.15、Go 1.26/1.27、Node.js 24/26 缓存 | 上游 `Install-Toolset.ps1`；本地脚本配置 Python 默认 3.14、Go 默认 1.27，并设置 PATH 和 GOROOT |
| Ruby 4.0 缓存、multi_json、fastlane | 上游 Ubuntu Ruby 安装脚本；gems 安装到系统 Ruby |
| CodeQL bundle | 上游 Ubuntu CodeQL 安装脚本，缓存当前 CodeQL Action 默认 bundle |
| 系统 Python 3、pip、pipx、yamllint、ansible-core | Python 和 pipx 复用上游 Ubuntu 安装脚本；本地脚本按 JSON 安装 pipx 工具，不额外注入 ansible 集合 |
| Java 8/17/21/25（默认 25）、Ant、Maven 3.x、Gradle | 上游 Ubuntu Java 安装脚本 |
| Rust stable、Cargo、rustfmt、Clippy | 上游 Ubuntu Rust 安装脚本 |
| .NET 8/10 SDK 和 nbgv | 本地安装脚本复用上游 helper 和 JSON 配置，每个版本系列只下载并安装最新稳定 SDK |
| Clang 21、最新版 CMake、Ninja、PowerShell 7.6、GitHub CLI、yq | 上游 Ubuntu 安装脚本 |
| Docker CLI、Buildx、Compose | 本地安装步骤，复用上游下载 helper，版本来自 JSON |

APT 工具跟随 Ubuntu 26.04 软件源；Rust、Gradle、GitHub CLI 等部分工具跟随上游脚本解析的版本。

生成 `en_US.UTF-8` 和 `zh_CN.UTF-8` locale（`locale -a` 中显示为 `en_US.utf8` 和 `zh_CN.utf8`），默认保持 `LANG=C`；job 可按需通过环境变量切换。

不安装 Docker Engine、containerd、runc、AWS CLI、Azure CLI、Google Cloud CLI，也不运行上游 VM 的 GRUB、Azure agent、systemd、内核参数和磁盘配置。保留 `sudo`，日常进程以 `runner` 用户执行。

上游脚本中的 `invoke_tests` 调用由本地 `check-tool.sh` 接管，执行对应工具的命令检查；遇到未知检查项会失败。这些检查不等同于上游完整 VM Pester 测试。最终检查以 runner 身份执行各版本缓存中的工具，并验证完成标记、nbgv、Ansible 和工具目录写权限，实际构建时执行。

## 环境变量

上游脚本通过 helper 修改 `/etc/environment`。`scripts/install-tools.sh` 集中列出安装步骤，通过 `set -euxo pipefail` 在构建日志中显示当前命令；`run_installer` 在每个脚本执行前重新加载环境文件，使前一步配置的 PATH、pipx 和 Java 变量可供下一步使用。Dockerfile 通过只读挂载调用安装脚本，工具安装、用户创建、权限配置和清理仍在同一条 `RUN` 中完成。

安装结束后，`configure-runner-environment.py` 将 `$HOME` 展开为 `/home/runner`，移除 shell 引号，并生成：

- `/home/runner/.env`：由 `Runner.Listener` 直接读取，包含工具 PATH 和工具变量，兼容 ARC 通过 `command: ["/home/runner/run.sh"]` 绕过 ENTRYPOINT 的启动方式。
- `/home/runner/.path`：供 runner 服务启动脚本读取。
- `/etc/runner-environment.sh`：供镜像默认 ENTRYPOINT 加载，支持直接运行工具命令。

工具链全部以 root 安装。安装完成后先修正 `/etc/skel` 中的 Cargo 环境文件，再创建 runner 用户，由 `adduser` 自动复制完整 skeleton 并设置所有权。工具安装、用户创建、home 所有权设置和 `chmod -R a+rwX /opt` 都在同一条 `RUN` 中完成，避免后续层因递归修改权限复制已有工具文件。`/opt` 对所有用户开放读写权限，目录及已有可执行文件保留执行权限。复制完成后在同一层删除 `/etc/skel` 中的 Cargo、Rustup 和 .NET 工具副本，工具保留在 runner home 中。保留上游对 npm、Java 等工具目录开放的写权限，支持 job 自行安装工具。不会把构建阶段的 `/root` 路径带入 runner 的工具 PATH。

`APT_MIRROR`、`DOCKER_HOST`、`XDG_RUNTIME_DIR` 和 ARC 注入的认证变量不写入 `.env`，可通过 Pod 的 `env` 配置。工具变量写入了 `.env`，runner 启动时会覆盖 Pod 中同名工具变量；更改这些值时需同步调整生成步骤。

## APT mirror

`BUILD_APT_MIRROR` 构建参数控制两个构建阶段的 Ubuntu 软件源；`RUNTIME_APT_MIRROR` 构建参数设置最终镜像默认使用的 Ubuntu 软件源。两者默认均为空，表示使用 Ubuntu 基础镜像的原始软件源。运行镜像不会继承构建阶段指定的 mirror。

运行时环境变量 `APT_MIRROR` 覆盖 `RUNTIME_APT_MIRROR`，显式设置为空可恢复原始 Ubuntu 软件源。地址必须为 HTTP(S) URL，指向包含 Ubuntu 仓库的根目录，例如 `https://mirror.example.com/ubuntu`。指定地址同时用于 Ubuntu 的主仓库和 security suites，mirror 需要包含相应内容；第三方仓库不受影响。

入口脚本以 runner 的 sudo 权限更新 `/etc/apt/sources.list.d/ubuntu.sources`，不会自动执行 `apt-get update`。直接运行容器可使用 `docker run -e APT_MIRROR=https://mirror.example.com/ubuntu ...`。若容器显式覆盖 ENTRYPOINT，需要自行调用 `/usr/local/bin/runner-entrypoint` 才能应用运行时 mirror。

ARC 的 `command` 会覆盖镜像 ENTRYPOINT。需要运行时 mirror 覆盖时，runner 容器配置为：

```yaml
command: ["/usr/local/bin/runner-entrypoint"]
args: ["/home/runner/run.sh"]
env:
  - name: APT_MIRROR
    value: https://mirror.example.com/ubuntu
```

## Docker sidecar

runner 镜像只携带 Docker 客户端。ARC Pod 需要另外配置 Docker sidecar。

- sidecar 的 Docker daemon 使用 UID/GID 1001，与 runner 一致。
- 将同一个 socket volume 挂载到两侧的 `/run/user/1001`，确保 runner 能访问 socket。
- 将同一个 work volume 挂载到两侧的 `/home/runner/_work`，保证容器挂载源路径一致。
- 依照 ARC 的 DinD 配置，将 runner 的 `externals` 共享给 sidecar，并配置 daemon 就绪检查。
- `docker:dind` 可能需要 privileged 等 Pod 权限，应按 ARC 和 Docker 官方文档配置。

参考：[ARC DinD 配置](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/deploy-runner-scale-sets)。

## 构建

```sh
git submodule update --init --recursive
docker build --platform linux/amd64 \
  --build-arg RUNNER_VERSION=2.338.2 \
  --build-arg IMAGE_VERSION=dev \
  --build-arg BUILD_APT_MIRROR=http://build-mirror.example.com/ubuntu \
  --build-arg RUNTIME_APT_MIRROR=https://runtime-mirror.example.com/ubuntu \
  -t actions-runner:2.338.2 .
```

`RUNNER_VERSION` 必须显式指定。
