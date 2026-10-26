#!/usr/bin/env bash
set -euxo pipefail

case "$1:${2:-}" in
    Apt:) git --version; git lfs version; ruby --version; php --version; composer --version ;;
    Tools:Python) python3 --version; pipx --version ;;
    Common:PipxPackages) /opt/pipx_bin/yamllint --version; /opt/pipx_bin/ansible --version ;;
    Tools:Ruby) ruby --version; gem list --local --exact multi_json --installed; gem list --local --exact fastlane --installed ;;
    Tools:clang) clang --version; clang++ --version; clang-format --version; clang-tidy --version ;;
    Tools:Cmake) cmake --version ;;
    Tools:Ninja) ninja --version ;;
    Java:) java -version; javac -version; mvn --version; gradle --version ;;
    Tools:Rust) /etc/skel/.cargo/bin/rustc --version; /etc/skel/.cargo/bin/cargo --version ;;
    DotnetSDK:) dotnet --list-sdks; /etc/skel/.dotnet/tools/nbgv --version ;;
    'CLI.Tools:GitHub CLI') gh --version ;;
    Tools:yq) yq --version ;;
    *) echo "Unhandled upstream test request: $*" >&2; exit 1 ;;
esac
