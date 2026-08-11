#!/usr/bin/env bash
# Export only the files needed to build/install the module in an appliance
# image. The destination must not already exist, which prevents stale payloads.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DESTINATION="${1:-}"

[[ -n "$DESTINATION" ]] || {
    echo "usage: scripts/export-appliance-payload.sh DESTINATION" >&2
    exit 2
}
[[ ! -e "$DESTINATION" ]] || {
    echo "destination already exists: $DESTINATION" >&2
    exit 2
}

install -d "$DESTINATION/compatibility" "$DESTINATION/src" "$DESTINATION/scripts"
install -m 0644 "$ROOT/VERSION" "$DESTINATION/"
install -m 0644 "$ROOT/compatibility/trixie.env" "$DESTINATION/compatibility/"
install -m 0644 "$ROOT/src/vfs_smbproxy_session.c" "$DESTINATION/src/"
install -m 0755 \
    "$ROOT/scripts/build-debian-package.sh" \
    "$ROOT/scripts/build-and-install.sh" \
    "$DESTINATION/scripts/"

echo "$DESTINATION"
