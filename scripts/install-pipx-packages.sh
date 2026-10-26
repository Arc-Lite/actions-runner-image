#!/usr/bin/env bash
set -euxo pipefail

# Install exactly the requested packages, without upstream's ansible injection.
# shellcheck disable=SC1091
source "$HELPER_SCRIPTS/install.sh"
export PATH="$PATH:$PIPX_BIN_DIR"
packages=$(get_toolset_value '.pipx[].package')
for package in $packages; do
    pipx install "$package"
done
invoke_tests Common PipxPackages
