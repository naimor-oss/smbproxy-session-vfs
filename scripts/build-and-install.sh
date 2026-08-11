#!/usr/bin/env bash
# Build the package for the Samba revision installed on this Trixie appliance,
# then install it through dpkg/apt so the exact dependency is enforced.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR=$(mktemp -d /tmp/smbproxy-session-vfs-package.XXXXXX)
trap 'rm -rf "$OUTPUT_DIR"' EXIT

INSTALLED_SAMBA_VERSION=$(dpkg-query -W -f='${Version}' samba)
# shellcheck disable=SC1091
source "$ROOT/compatibility/trixie.env"
if [[ "$INSTALLED_SAMBA_VERSION" != "$SAMBA_DEB_VERSION" ]]; then
    echo "installed Samba $INSTALLED_SAMBA_VERSION is not the qualified component target $SAMBA_DEB_VERSION" >&2
    echo "qualify the revision and advance compatibility/trixie.env before building an appliance" >&2
    exit 2
fi
SMBPROXY_VFS_AUTOREMOVE=1 \
    "$ROOT/scripts/build-debian-package.sh" \
        --samba-version "$INSTALLED_SAMBA_VERSION" \
        --output-dir "$OUTPUT_DIR" >/dev/null

PACKAGE=$(find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.deb' -print -quit)
[[ -n "$PACKAGE" ]] || { echo "VFS package was not produced" >&2; exit 5; }
DEBIAN_FRONTEND=noninteractive apt-get install -y "$PACKAGE"

echo "installed smbproxy-session-vfs for Debian Samba $INSTALLED_SAMBA_VERSION"
