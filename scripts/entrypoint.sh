#!/usr/bin/env bash
set -eo pipefail
# ARC's command can bypass ENTRYPOINT. Runner.Listener also loads the same values
# from /home/runner/.env; no dependency on a login shell or PAM is required.
# shellcheck disable=SC1091
source /etc/runner-environment.sh
if [[ "$EUID" -eq 0 ]]; then
    /usr/local/bin/configure-apt-mirror "${APT_MIRROR:-}"
else
    sudo -- /usr/local/bin/configure-apt-mirror "${APT_MIRROR:-}"
fi
exec "$@"
