#!/usr/bin/env bash
set -euxo pipefail

# Reuse the upstream toolset format and environment helpers without running the
# VM-specific Pester suite from Configure-Toolset.ps1.
# shellcheck disable=SC1091
source "$HELPER_SCRIPTS/install.sh"
# shellcheck disable=SC1091
source "$HELPER_SCRIPTS/etc-environment.sh"

python_arch=$(get_toolset_value '.toolcache[] | select(.name == "Python") | .arch')
python_default=$(get_toolset_value '.toolcache[] | select(.name == "Python") | .default')
mapfile -t matches < <(compgen -G "$AGENT_TOOLSDIRECTORY/Python/$python_default/$python_arch" | sort -V)
if ((${#matches[@]} == 0)); then
    echo "Missing default Python cache: $python_default ($python_arch)" >&2
    exit 1
fi
selected=${matches[-1]}
test -f "${selected}.complete"
prepend_etc_environment_path "$selected/bin"

go_arch=$(get_toolset_value '.toolcache[] | select(.name == "go") | .arch')
go_default=$(get_toolset_value '.toolcache[] | select(.name == "go") | .default')
go_versions=$(get_toolset_value '.toolcache[] | select(.name == "go") | .versions[]')
for pattern in $go_versions; do
    mapfile -t matches < <(compgen -G "$AGENT_TOOLSDIRECTORY/go/$pattern/$go_arch" | sort -V)
    if ((${#matches[@]} == 0)); then
        echo "Missing Go cache: $pattern ($go_arch)" >&2
        exit 1
    fi
    selected=${matches[-1]}
    test -f "${selected}.complete"
    version=${pattern%.*}
    set_etc_environment_variable "GOROOT_${version//./_}_X64" "$selected"
    if [[ "$pattern" == "$go_default" ]]; then
        ln -s "$selected/bin/go" /usr/local/bin/go
        ln -s "$selected/bin/gofmt" /usr/local/bin/gofmt
        set_etc_environment_variable GOROOT "$selected"
    fi
done
go version
