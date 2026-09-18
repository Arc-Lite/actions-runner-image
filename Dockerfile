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

# Avoid interactive prompts
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
    /tmp/scripts/build/install-ms-repos.sh && \
    /tmp/scripts/build/configure-image-data-file.sh && \
    /tmp/scripts/build/configure-environment.sh && \
    /tmp/scripts/build/install-actions-cache.sh && \
    /tmp/scripts/build/install-apt-common.sh && \
    /tmp/scripts/build/install-azcopy.sh && \
    /tmp/scripts/build/install-azure-cli.sh && \
    /tmp/scripts/build/install-azure-devops-cli.sh && \
    /tmp/scripts/build/install-bicep.sh && \
    /tmp/scripts/build/install-aws-tools.sh && \
    /tmp/scripts/build/install-git.sh && \
    /tmp/scripts/build/install-git-lfs.sh && \
    /tmp/scripts/build/install-github-cli.sh && \
    /tmp/scripts/build/install-google-cloud-cli.sh && \
    /tmp/scripts/build/install-nvm.sh && \
    /tmp/scripts/build/install-nodejs.sh && \
    /tmp/scripts/build/install-powershell.sh && \
    /tmp/scripts/build/configure-dpkg.sh && \
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

# Install the runtime libraries previously supplied by the .NET base image.
RUN ./bin/installdependencies.sh

# Load slim's environment even when ARC invokes run.sh directly.
RUN sed -i '1a set -a\nsource /etc/environment\nset +a' /home/runner/run.sh

USER runner

ENTRYPOINT ["/home/runner/run.sh"]
