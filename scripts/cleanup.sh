#!/usr/bin/env bash
set -euo pipefail

apt-get clean
rm -f /etc/apt/apt.conf.d/99runner-image-build
rm -rf /var/lib/apt/lists/* \
    /usr/local/n/versions \
    /root/.cache /root/.npm /root/.nuget /root/.dotnet /root/.gradle /root/.m2
# Keep the read-only source mounts; remove scratch data beside them.
find /tmp -mindepth 1 -maxdepth 1 ! -path /tmp/runner-image-sources -exec rm -rf -- {} +
