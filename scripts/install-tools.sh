#!/usr/bin/env bash
set -euxo pipefail

export HELPER_SCRIPTS=/tmp/runner-image-sources/upstream/ubuntu/scripts/helpers
export INSTALLER_SCRIPT_FOLDER=/tmp/runner-image-sources/toolsets
ubuntu_scripts=/tmp/runner-image-sources/upstream/ubuntu/scripts/build
slim_scripts=/tmp/runner-image-sources/upstream/ubuntu-slim/scripts/build
printf 'APT::Get::Assume-Yes "true";\n' > /etc/apt/apt.conf.d/99runner-image-assume-yes
install -d /tmp/runner-image-build
cd /tmp/runner-image-build
apt-get update
invoke_tests() {
    bash /tmp/runner-image-sources/scripts/check-tool.sh "$@"
}
export -f invoke_tests
printf 'PATH=%s\n' "$PATH" > /etc/environment
printf 'AGENT_TOOLSDIRECTORY=%s\nRUNNER_TOOL_CACHE=%s\n' \
    "$AGENT_TOOLSDIRECTORY" "$RUNNER_TOOL_CACHE" >> /etc/environment
run_installer() {
    set -a
    # shellcheck disable=SC1091
    source /etc/environment
    set +a
    bash -e "$1"
}
run_installer "$ubuntu_scripts/install-apt-vital.sh"
run_installer "$ubuntu_scripts/install-apt-common.sh"
printf 'en_US.UTF-8 UTF-8\nzh_CN.UTF-8 UTF-8\n' > /etc/locale.gen
locale-gen
update-locale --reset LANG=C
run_installer "$slim_scripts/install-nodejs.sh"
run_installer "$ubuntu_scripts/install-python.sh"
run_installer /tmp/runner-image-sources/scripts/install-pipx-packages.sh
run_installer "$ubuntu_scripts/install-powershell.sh"
# The upstream cache installer imports its helpers from the mounted scripts tree.
# It expects SUDO_USER for its ownership step even when installation runs as root.
# shellcheck disable=SC2016
SUDO_USER=root pwsh -NoLogo -NoProfile -Command \
    '$ErrorActionPreference = "Stop"; $PSNativeCommandUseErrorActionPreference = $true; & "$env:HELPER_SCRIPTS/../build/Install-Toolset.ps1"'
run_installer /tmp/runner-image-sources/scripts/configure-toolcache.sh
run_installer "$ubuntu_scripts/install-ruby.sh"
run_installer "$ubuntu_scripts/install-codeql-bundle.sh"
run_installer "$ubuntu_scripts/install-clang.sh"
run_installer "$ubuntu_scripts/install-cmake.sh"
run_installer "$ubuntu_scripts/install-ninja.sh"
run_installer "$ubuntu_scripts/install-java-tools.sh"
run_installer "$ubuntu_scripts/install-rust.sh"
run_installer /tmp/runner-image-sources/scripts/install-dotnet.sh
run_installer "$ubuntu_scripts/install-github-cli.sh"
run_installer "$ubuntu_scripts/install-yq.sh"
# shellcheck disable=SC1091
source "$HELPER_SCRIPTS/install.sh"
docker_version=$(get_toolset_value '.docker.components[] | select(.package == "docker-ce-cli") | .version')
archive=$(download_with_retry "https://download.docker.com/linux/static/stable/x86_64/docker-${docker_version}.tgz" /tmp/docker-client.tgz)
tar xzf "$archive" -C /tmp docker/docker
install -m 0755 /tmp/docker/docker /usr/local/bin/docker
rm -rf /tmp/docker "$archive"
install -d /usr/local/lib/docker/cli-plugins
while IFS=$'\t' read -r plugin version asset; do
    case "$plugin" in
        buildx) url="https://github.com/docker/buildx/releases/download/v${version}/buildx-v${version}.${asset}" ;;
        compose) url="https://github.com/docker/compose/releases/download/v${version}/docker-compose-${asset}" ;;
        *) echo "Unsupported Docker plugin: $plugin" >&2; exit 1 ;;
    esac
    archive=$(download_with_retry "$url" "/tmp/docker-${plugin}")
    install -m 0755 "$archive" "/usr/local/lib/docker/cli-plugins/docker-${plugin}"
    rm -f "$archive"
done < <(jq -r '.docker.plugins[] | [.plugin, .version, .asset] | @tsv' "$INSTALLER_SCRIPT_FOLDER/toolset.json")
sed -i 's|/etc/skel/.cargo|/home/runner/.cargo|g' /etc/skel/.cargo/env
install -d /etc/skel/.local/bin /etc/skel/.config
install -m 0644 "$INSTALLER_SCRIPT_FOLDER/toolset.json" /opt/toolset.json
