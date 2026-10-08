#!/usr/bin/env bash
# Build the package for the qualified Samba revision in compatibility/trixie.env
# (installing that revision if the image has a different one), then install
# it through dpkg/apt so the exact dependency is enforced.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR=$(mktemp -d /tmp/smbproxy-session-vfs-package.XXXXXX)
trap 'rm -rf "$OUTPUT_DIR"' EXIT

# shellcheck disable=SC1091
source "$ROOT/compatibility/trixie.env"
INSTALLED_SAMBA_VERSION=$(dpkg-query -W -f='${Version}' samba 2>/dev/null || true)
if [[ "$INSTALLED_SAMBA_VERSION" != "$SAMBA_DEB_VERSION" ]]; then
    # A fresh image installs Debian's newest Samba, which is usually newer
    # than the last qualified revision. Build for the qualified revision;
    # build-debian-package.sh pins the whole samba source family to it,
    # downgrading if needed. This runs during image construction only.
    echo "Samba ${INSTALLED_SAMBA_VERSION:-not installed} is not the qualified $SAMBA_DEB_VERSION;" \
        "installing the qualified revision for this image" >&2
fi
SMBPROXY_VFS_AUTOREMOVE=1 \
    "$ROOT/scripts/build-debian-package.sh" \
        --samba-version "$SAMBA_DEB_VERSION" \
        --output-dir "$OUTPUT_DIR" >/dev/null
INSTALLED_SAMBA_VERSION=$(dpkg-query -W -f='${Version}' samba)
[[ "$INSTALLED_SAMBA_VERSION" == "$SAMBA_DEB_VERSION" ]] || {
    echo "Samba $INSTALLED_SAMBA_VERSION is installed after the build; expected $SAMBA_DEB_VERSION" >&2
    exit 2
}

PACKAGE=$(find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.deb' -print -quit)
[[ -n "$PACKAGE" ]] || { echo "VFS package was not produced" >&2; exit 5; }
DEBIAN_FRONTEND=noninteractive apt-get install -y "$PACKAGE"

echo "installed smbproxy-session-vfs for Debian Samba $INSTALLED_SAMBA_VERSION"
