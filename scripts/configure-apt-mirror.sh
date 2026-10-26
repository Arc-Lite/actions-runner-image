#!/usr/bin/env bash
set -euo pipefail

mirror=${1:-}
sources=/etc/apt/sources.list.d/ubuntu.sources
template=/usr/local/share/runner-image/ubuntu.sources

if [[ -n "$mirror" && ! "$mirror" =~ ^https?://[^[:space:]]+$ ]]; then
    echo 'APT mirror must be an http:// or https:// URL without whitespace' >&2
    exit 1
fi

# Preserve the base image's Ubuntu definitions before applying a build mirror.
# All runtime changes start from this template, leaving third-party repos alone.
if [[ ! -f "$template" ]]; then
    install -D -m 0644 "$sources" "$template"
fi

temporary=$(mktemp)
trap 'rm -f "$temporary"' EXIT
if [[ -n "$mirror" ]]; then
    RUNNER_IMAGE_APT_MIRROR="$mirror" awk '
        /^URIs:/ { print "URIs: " ENVIRON["RUNNER_IMAGE_APT_MIRROR"]; next }
        { print }
    ' "$template" > "$temporary"
else
    cp "$template" "$temporary"
fi

# No apt update here: jobs decide when to refresh package indexes.
if ! cmp -s "$temporary" "$sources"; then
    install -m 0644 "$temporary" "$sources"
fi
