#!/usr/bin/env bash
set -euxo pipefail

# Reuse upstream helpers and the toolset, installing one SDK per release series.
# shellcheck disable=SC1091
source "$HELPER_SCRIPTS/install.sh"
# shellcheck disable=SC1091
source "$HELPER_SCRIPTS/etc-environment.sh"

export DOTNET_CLI_TELEMETRY_OPTOUT=1
apt-get install --no-install-recommends \
    ca-certificates libc6 libgcc-s1 libgssapi-krb5-2 liblttng-ust1t64 \
    libssl3t64 libstdc++6 libicu78 zlib1g

install -d /usr/share/dotnet
installer=$(download_with_retry https://dot.net/v1/dotnet-install.sh /tmp/runner-image-build/dotnet-install.sh)
series_list=$(get_toolset_value '.dotnet.versions[]')
for series in $series_list; do
    metadata=$(download_with_retry "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/$series/releases.json" \
        "/tmp/runner-image-build/dotnet-$series-releases.json")
    sdk=$(jq -er '."latest-sdk" | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' "$metadata")
    [[ "$sdk" == "$series".* ]]
    echo "Installing latest .NET $series SDK: $sdk"
    bash "$installer" --version "$sdk" --install-dir /usr/share/dotnet --no-path
    rm -f "$metadata"
done
rm -f "$installer"
ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet

set_etc_environment_variable DOTNET_SKIP_FIRST_TIME_EXPERIENCE 1
set_etc_environment_variable DOTNET_NOLOGO 1
set_etc_environment_variable DOTNET_MULTILEVEL_LOOKUP 0
# shellcheck disable=SC2016
prepend_etc_environment_path '$HOME/.dotnet/tools'

tools=$(get_toolset_value '.dotnet.tools[].name')
for tool in $tools; do
    dotnet tool install "$tool" --tool-path /etc/skel/.dotnet/tools
done
invoke_tests DotnetSDK
