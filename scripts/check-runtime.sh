#!/usr/bin/env bash
set -euxo pipefail

node --version
npm --version
n --version
yarn --version
python3 --version
python_default=$(jq -r '.toolcache[] | select(.name == "Python") | .default' /opt/toolset.json)
test "$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')" = "${python_default%.*}"
test "$(node -p 'process.versions.node.split(".")[0]')" = "$(jq -r '.node.default' /opt/toolset.json)"
test ! -d /usr/local/n/versions
go version
gcc --version
g++ --version
rustc --version
cargo --version
rustup show active-toolchain
java -version
dotnet --list-sdks
mapfile -t sdks < <(dotnet --list-sdks | awk '{print $1}')
mapfile -t series_list < <(jq -r '.dotnet.versions[]' /opt/toolset.json)
test "${#sdks[@]}" -eq "${#series_list[@]}"
for series in "${series_list[@]}"; do
    count=0
    for sdk in "${sdks[@]}"; do
        if [[ "$sdk" == "$series".* ]]; then
            count=$((count + 1))
        fi
    done
    test "$count" -eq 1
done
nbgv --version
ansible --version
"$PIPX_HOME/venvs/ansible-core/bin/python" -c 'from importlib.metadata import distributions; assert not any(d.metadata["Name"].lower() == "ansible" for d in distributions())'
# shellcheck disable=SC2016
pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
docker --version
docker buildx version
docker compose version
test -w "$RUNNER_TOOL_CACHE"
test -w "$PIPX_HOME"
test -w "$PIPX_BIN_DIR"
test -w "$CARGO_HOME"
test -w "$RUSTUP_HOME"
test -d "$JAVA_HOME"
bash "$(dirname "${BASH_SOURCE[0]}")/check-toolcache.sh"
