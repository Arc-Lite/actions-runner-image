FROM ubuntu:24.04 AS build

ARG TARGETOS=linux
ARG TARGETARCH=amd64
ARG RUNNER_VERSION
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.7.0

RUN apt update -y && apt install ca-certificates curl unzip -y

WORKDIR /actions-runner
RUN export RUNNER_ARCH=${TARGETARCH} \
    && if [ "$RUNNER_ARCH" = "amd64" ]; then export RUNNER_ARCH=x64 ; fi \
    && curl -f -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${TARGETOS}-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./runner.tar.gz \
    && rm runner.tar.gz

RUN curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip \
    && unzip ./runner-container-hooks.zip -d ./k8s \
    && rm runner-container-hooks.zip

RUN curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v0.8.1/actions-runner-hooks-k8s-0.8.1.zip \
    && unzip ./runner-container-hooks.zip -d ./k8s-novolume \
    && rm runner-container-hooks.zip

RUN sed -i '1a set -a\nsource /etc/environment\nset +a' /actions-runner/run.sh

FROM ubuntu:24.04 AS toolcache

ENV DEBIAN_FRONTEND=noninteractive
ENV AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache
ENV RUNNER_TOOL_CACHE=/opt/hostedtoolcache
ENV HELPER_SCRIPTS=/tmp/scripts/helpers

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl jq tar gzip xz-utils libpython3.12 libssl3t64 libffi8 libbz2-1.0 liblzma5 libsqlite3-0 libreadline8t64 libncursesw6 libgdbm6t64 libuuid1 tk \
    && rm -rf /var/lib/apt/lists/*

COPY --link toolsets/toolset.json /tmp/toolsets/toolset.json
COPY --link scripts/build/install-hostedtoolcache.sh /tmp/install-hostedtoolcache.sh
RUN bash /tmp/install-hostedtoolcache.sh /tmp/toolsets/toolset.json

COPY --link scripts/helpers/install.sh /tmp/scripts/helpers/install.sh
COPY --link scripts/build/install-codeql-bundle.sh /tmp/install-codeql-bundle.sh
RUN bash -e /tmp/install-codeql-bundle.sh

FROM ubuntu:24.04 AS base

ARG IMAGE_VERSION=1.0.0
ARG IMAGE_OWNER="GitHub"

ENV IMAGE_OWNER=$IMAGE_OWNER
ENV ImageVersion=$IMAGE_VERSION
ENV IMAGE_VERSION=$IMAGE_VERSION
ENV ImageOS=ubuntu24
ENV IMAGE_OS=ubuntu24
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1
ENV IMAGE_TARGET_PLATFORM="GitHub"
ENV POWERSHELL_DISTRIBUTION_CHANNEL="GitHub-Actions-$ImageOS"
ENV IMAGEDATA_NAME="ubuntu:24.04"
ENV NVM_DIR="/etc/skel/.nvm"
ENV HELPER_SCRIPTS="/tmp/scripts/helpers"
ENV INSTALLER_SCRIPT_FOLDER="/tmp/toolsets"
ENV AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache
ENV RUNNER_TOOL_CACHE=/opt/hostedtoolcache

ENV DEBIAN_FRONTEND=noninteractive

COPY scripts/build /tmp/scripts/build
COPY scripts/helpers /tmp/scripts/helpers
COPY toolsets/ /tmp/toolsets/
RUN find /tmp/scripts -name "*.sh" -type f -exec chmod +x {} \;

RUN echo 'set -eo pipefail' >> /etc/bash.bashrc

RUN apt-get update && apt-get upgrade -y && apt-get install -y sudo lsb-release jq dpkg && \
    touch /run/.containerenv && \
    /tmp/scripts/build/configure-apt-sources.sh && \
    /tmp/scripts/build/configure-apt.sh && \
    /tmp/scripts/build/install-apt-vital.sh && \
    /tmp/scripts/build/configure-image-data-file.sh && \
    /tmp/scripts/build/configure-environment.sh && \
    /tmp/scripts/build/install-actions-cache.sh && \
    /tmp/scripts/build/install-apt-common.sh && \
    /tmp/scripts/build/install-git.sh && \
    /tmp/scripts/build/install-git-lfs.sh && \
    /tmp/scripts/build/configure-dpkg.sh && \
    /tmp/scripts/helpers/cleanup.sh

RUN apt-get update && \
    /tmp/scripts/build/install-github-cli.sh && \
    /tmp/scripts/build/install-java-tools.sh && \
    /tmp/scripts/build/install-dotnetcore-sdk.sh && \
    /tmp/scripts/build/install-clang.sh && \
    /tmp/scripts/build/install-gcc-compilers.sh && \
    /tmp/scripts/build/install-gfortran.sh && \
    /tmp/scripts/build/install-cmake.sh && \
    /tmp/scripts/build/install-ninja.sh && \
    /tmp/scripts/build/install-rust.sh && \
    /tmp/scripts/build/install-ruby.sh && \
    /tmp/scripts/build/install-terraform.sh && \
    /tmp/scripts/build/install-oras-cli.sh && \
    /tmp/scripts/build/install-nvm.sh && \
    /tmp/scripts/build/install-nodejs.sh && \
    /tmp/scripts/build/install-vcpkg.sh && \
    /tmp/scripts/build/install-yq.sh && \
    /tmp/scripts/build/install-python.sh && \
    /tmp/scripts/build/install-zstd.sh && \
    /tmp/scripts/build/install-pipx-packages.sh && \
    /tmp/scripts/build/install-docker-cli.sh && \
    /tmp/scripts/build/configure-system.sh && \
    /tmp/scripts/helpers/cleanup.sh

RUN sed -i '/set -eo pipefail/d' /etc/bash.bashrc

RUN adduser --disabled-password --gecos "" --uid 1001 runner \
    && groupadd docker --gid 123 \
    && usermod -aG sudo runner \
    && usermod -aG docker runner \
    && echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers \
    && echo "Defaults env_keep += \"DEBIAN_FRONTEND\"" >> /etc/sudoers \
    && chmod 777 /home/runner

WORKDIR /home/runner

COPY --link --chown=1001:123 --from=build /actions-runner .
COPY --link --chown=1001:123 --from=toolcache /opt/hostedtoolcache/ /opt/hostedtoolcache/

RUN ./bin/installdependencies.sh

USER runner
