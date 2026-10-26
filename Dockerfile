# syntax=docker/dockerfile:1
# Skeleton: actions/runner/images/Dockerfile. Build from this directory.
ARG BUILD_APT_MIRROR=
FROM ubuntu:26.04 AS runner-download
SHELL ["/bin/bash", "-c"]

ARG BUILD_APT_MIRROR
ARG TARGETOS
ARG TARGETARCH
ARG RUNNER_VERSION
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.7.0
ARG RUNNER_CONTAINER_HOOKS_NOVOLUME_VERSION=0.8.1

RUN --mount=type=bind,source=scripts,target=/tmp/runner-image-sources/scripts,readonly \
    set -euxo pipefail; \
    bash /tmp/runner-image-sources/scripts/configure-apt-mirror.sh "$BUILD_APT_MIRROR"; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl unzip; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*
WORKDIR /actions-runner
RUN set -euxo pipefail; \
    test -n "${RUNNER_VERSION}"; \
    test "${TARGETOS}" = linux; \
    case "${TARGETARCH}" in amd64) runner_arch=x64 ;; *) echo 'Only linux/amd64 is supported by this toolset' >&2; exit 1 ;; esac; \
    curl -fL --retry 5 -o runner.tar.gz "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${TARGETOS}-${runner_arch}-${RUNNER_VERSION}.tar.gz"; \
    tar xzf runner.tar.gz; \
    rm runner.tar.gz
RUN set -euxo pipefail; \
    curl -fL --retry 5 -o hooks.zip "https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip"; \
    unzip hooks.zip -d k8s; \
    rm hooks.zip; \
    curl -fL --retry 5 -o hooks.zip "https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_NOVOLUME_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_NOVOLUME_VERSION}.zip"; \
    unzip hooks.zip -d k8s-novolume; \
    rm hooks.zip

FROM ubuntu:26.04 AS runner
SHELL ["/bin/bash", "-c"]

ARG BUILD_APT_MIRROR
ARG IMAGE_VERSION=dev
ENV RUNNER_MANUALLY_TRAP_SIG=1 \
    ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1 \
    DEBIAN_FRONTEND=noninteractive \
    ImageOS=ubuntu26 \
    ImageVersion=${IMAGE_VERSION} \
    LANG=C \
    AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache \
    RUNNER_TOOL_CACHE=/opt/hostedtoolcache

# Install prerequisites as root before running the upstream tool installers.
RUN --mount=type=bind,source=scripts,target=/tmp/runner-image-sources/scripts,readonly \
    set -euxo pipefail; \
    bash /tmp/runner-image-sources/scripts/configure-apt-mirror.sh "$BUILD_APT_MIRROR"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        sudo lsb-release ca-certificates curl jq unzip gnupg software-properties-common python3; \
    install -d -m 0755 /opt/hostedtoolcache; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Trace each installer in the build log; upstream scripts run in their own Bash.
RUN --mount=type=bind,source=upstream/runner-images/images/ubuntu/scripts,target=/tmp/runner-image-sources/upstream/ubuntu/scripts,readonly \
    --mount=type=bind,source=upstream/runner-images/images/ubuntu-slim/scripts,target=/tmp/runner-image-sources/upstream/ubuntu-slim/scripts,readonly \
    --mount=type=bind,source=toolsets,target=/tmp/runner-image-sources/toolsets,readonly \
    --mount=type=bind,source=scripts,target=/tmp/runner-image-sources/scripts,readonly \
    set -euxo pipefail; \
    bash /tmp/runner-image-sources/scripts/install-tools.sh; \
    adduser --disabled-password --gecos "" --uid 1001 runner; \
    groupadd docker --gid 123; \
    usermod -aG sudo,docker runner; \
    chown -R runner:docker /home/runner; \
    chmod -R a+rwX /opt; \
    rm -rf /etc/skel/.cargo /etc/skel/.rustup /etc/skel/.dotnet; \
    printf 'runner ALL=(ALL:ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/runner; \
    chmod 0440 /etc/sudoers.d/runner; \
    install -d -o runner -g runner -m 0700 /run/user/1001; \
    bash /tmp/runner-image-sources/scripts/cleanup.sh

ENV XDG_RUNTIME_DIR=/run/user/1001
WORKDIR /home/runner
COPY --link --chown=1001:123 --from=runner-download /actions-runner/ ./
ARG RUNTIME_APT_MIRROR=
ENV APT_MIRROR=${RUNTIME_APT_MIRROR}
RUN --mount=type=bind,source=scripts,target=/tmp/runner-image-sources/scripts,readonly \
    set -euxo pipefail; \
    bash /home/runner/bin/installdependencies.sh; \
    install -m 0755 /tmp/runner-image-sources/scripts/configure-apt-mirror.sh /usr/local/bin/configure-apt-mirror; \
    /usr/local/bin/configure-apt-mirror "$APT_MIRROR"; \
    python3 /tmp/runner-image-sources/scripts/configure-runner-environment.py; \
    install -m 0755 /tmp/runner-image-sources/scripts/entrypoint.sh /usr/local/bin/runner-entrypoint; \
    chown runner:docker /home/runner/.env /home/runner/.path; \
    runuser -u runner -- /usr/local/bin/runner-entrypoint \
        bash /tmp/runner-image-sources/scripts/check-runtime.sh; \
    bash /tmp/runner-image-sources/scripts/cleanup.sh

USER runner
ENTRYPOINT ["/usr/local/bin/runner-entrypoint"]
CMD ["/home/runner/run.sh"]
