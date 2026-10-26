#!/usr/bin/env bash
set -euxo pipefail

while IFS=$'\t' read -r name arch pattern; do
    mapfile -t matches < <(compgen -G "$RUNNER_TOOL_CACHE/$name/$pattern/$arch" | sort -V)
    if ((${#matches[@]} == 0)); then
        echo "Missing toolcache entry: $name $pattern ($arch)" >&2
        exit 1
    fi
    cached=${matches[-1]}
    test -f "${cached}.complete"
    case "$name" in
        Python) LD_LIBRARY_PATH="$cached/lib:${LD_LIBRARY_PATH:-}" "$cached/bin/python" --version ;;
        node) "$cached/bin/node" --version ;;
        go) GOROOT="$cached" "$cached/bin/go" version ;;
        Ruby) "$cached/bin/ruby" --version ;;
        CodeQL) "$cached/codeql/codeql" version ;;
        *) echo "Unhandled toolcache entry: $name" >&2; exit 1 ;;
    esac
done < <(jq -r '.toolcache[] | . as $tool | .versions[] | [$tool.name, $tool.arch, .] | @tsv' /opt/toolset.json)
