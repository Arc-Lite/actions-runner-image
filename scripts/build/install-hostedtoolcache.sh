#!/bin/bash
set -euo pipefail

toolset=${1:-${INSTALLER_SCRIPT_FOLDER:?}/toolset.json}
export AGENT_TOOLSDIRECTORY=${AGENT_TOOLSDIRECTORY:-/opt/hostedtoolcache}
export RUNNER_TOOL_CACHE=$AGENT_TOOLSDIRECTORY
mkdir -p "$AGENT_TOOLSDIRECTORY"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

download() {
    curl --fail --silent --show-error --location --retry 3 --connect-timeout 30 \
        --output "$2" "$1"
}

check_cache() {
    local path="$AGENT_TOOLSDIRECTORY/$1/$2/$3"
    if [[ ! -d "$path" || ! -f "$path.complete" ]]; then
        echo "Incomplete toolcache: $1 $2 $3" >&2
        exit 1
    fi
}

install_manifest_tool() {
    local tool=$1 name arch pattern version url selected
    name=$(jq -r '.name' <<< "$tool")
    arch=$(jq -r '.arch' <<< "$tool")
    download "$(jq -r '.url' <<< "$tool")" "$work/manifest.json"
    # Preserve manifest order, matching Install-Toolset.ps1's first-match selection.
    jq -r --argjson tool "$tool" '
        .[] | select(.version | test("^[0-9]+(\\.[0-9]+){1,3}$")) |
        .version as $version | .files[] |
        select(.platform == $tool.platform and .arch == $tool.arch and
               .platform_version == $tool.platform_version) |
        [$version, .download_url] | @tsv
    ' "$work/manifest.json" > "$work/candidates.tsv"

    while IFS= read -r pattern; do
        selected=false
        while IFS=$'\t' read -r version url; do
            # Version requirements deliberately use shell globs, such as 22.*.
            # shellcheck disable=SC2053
            if [[ $version == $pattern ]]; then
                selected=true
                break
            fi
        done < "$work/candidates.tsv"
        if [[ $selected != true ]]; then
            echo "No release matches $name $pattern $arch" >&2
            exit 1
        fi
        echo "Installing $name $version ($arch)"
        download "$url" "$work/asset.tar.gz"
        mkdir "$work/asset"
        tar -xzf "$work/asset.tar.gz" -C "$work/asset"
        (cd "$work/asset" && bash ./setup.sh)
        check_cache "$name" "$version" "$arch"
        rm -rf "$work/asset" "$work/asset.tar.gz"
    done < <(jq -r '.versions[]' <<< "$tool")
}

# Materialize the input first so malformed JSON fails before the installation loop.
# Tools without a manifest URL are installed by their dedicated build scripts.
jq -c '.toolcache[] | select(.url != null)' "$toolset" > "$work/tools.jsonl"
while IFS= read -r tool; do
    install_manifest_tool "$tool"
done < "$work/tools.jsonl"
