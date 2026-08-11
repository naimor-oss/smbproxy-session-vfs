#!/usr/bin/env bash
# Compare the accepted Samba revision with the current candidate in configured
# Debian Trixie sources. Exit 10 when a new or otherwise different candidate
# needs qualification.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/compatibility/trixie.env"

candidate=$(apt-cache policy samba \
    | awk '/Candidate:/ { print $2; exit }')
[[ -n "$candidate" && "$candidate" != "(none)" ]] || {
    echo "no Samba candidate in configured APT sources" >&2
    exit 2
}

printf 'tracked=%s\n' "$SAMBA_DEB_VERSION"
printf 'candidate=%s\n' "$candidate"
if [[ "$candidate" != "$SAMBA_DEB_VERSION" ]]; then
    echo "qualification required"
    exit 10
fi
echo "tracked revision is current"
