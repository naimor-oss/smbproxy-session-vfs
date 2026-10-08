#!/usr/bin/env bash
#===============================================================================
# build-debian-package.sh — build an exact-Samba-revision VFS Debian package
#
# Samba's public development package does not expose the source3 VFS internals
# used by this module. This script obtains the matching Debian source package,
# uses Debian's own configure target, builds only vfs_smbproxy_session, and
# emits a binary package with an exact dependency on the Samba binary revision.
#===============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODULE_SOURCE="$ROOT/src/vfs_smbproxy_session.c"
OUTPUT_DIR="$ROOT/dist"
SAMBA_DEB_VERSION="${SAMBA_DEB_VERSION:-}"

usage() {
    cat <<USAGE
Usage: scripts/build-debian-package.sh [options]

Options:
  --samba-version VERSION  Exact Debian samba package revision. Defaults to
                           the installed revision, then compatibility/trixie.env.
  --source FILE            VFS C source (default: src/vfs_smbproxy_session.c)
  --output-dir DIR         Artifact directory (default: dist/)
  -h, --help               Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --samba-version) SAMBA_DEB_VERSION="$2"; shift 2 ;;
        --source) MODULE_SOURCE="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ $EUID -eq 0 ]] || { echo "run as root (a disposable Trixie builder is recommended)" >&2; exit 2; }
[[ -f "$MODULE_SOURCE" ]] || { echo "missing VFS source: $MODULE_SOURCE" >&2; exit 2; }

if [[ -z "$SAMBA_DEB_VERSION" ]]; then
    SAMBA_DEB_VERSION=$(dpkg-query -W -f='${Version}' samba 2>/dev/null || true)
fi
if [[ -z "$SAMBA_DEB_VERSION" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT/compatibility/trixie.env"
fi
[[ -n "$SAMBA_DEB_VERSION" ]] || { echo "Samba package revision is empty" >&2; exit 2; }

BUILD_ROOT=$(mktemp -d /tmp/smbproxy-session-vfs-build.XXXXXX)
MANUAL_BEFORE="$BUILD_ROOT/manual-before"
SOURCE_LIST=/etc/apt/sources.list.d/smbproxy-session-vfs-build.sources
SOURCE_LIST_CREATED=0
# Every binary built from the samba source carries the same version and
# depends on its siblings with "=". Asking apt for samba=<old> alone fails
# once a newer point release exists, because samba-common-bin, samba-libs,
# ... still resolve to the newest candidate. A temporary source pin moves
# the whole family to the target revision together.
SAMBA_PIN=/etc/apt/preferences.d/smbproxy-session-vfs-build-samba.pref
MANUAL_MARKS_RESTORED=0

restore_manual_marks() {
    [[ $MANUAL_MARKS_RESTORED -eq 0 && -f "$MANUAL_BEFORE" ]] || return 0
    apt-mark showmanual | sort > "$BUILD_ROOT/manual-after"
    comm -13 "$MANUAL_BEFORE" "$BUILD_ROOT/manual-after" > "$BUILD_ROOT/manual-new"
    if [[ -s "$BUILD_ROOT/manual-new" ]]; then
        xargs apt-mark auto < "$BUILD_ROOT/manual-new" >/dev/null
    fi
    MANUAL_MARKS_RESTORED=1
}

cleanup() {
    local rc=$?
    trap - EXIT
    set +e
    restore_manual_marks
    [[ $SOURCE_LIST_CREATED -eq 0 ]] || rm -f "$SOURCE_LIST"
    rm -f "$SAMBA_PIN"
    rm -rf "$BUILD_ROOT"
    exit "$rc"
}
trap cleanup EXIT

apt-mark showmanual | sort > "$MANUAL_BEFORE"
# Bundled libraries carry their own upstream version with the Samba
# revision as a suffix (libldb2 2:2.11.0+samba4.22.10+dfsg-0+deb13u2), so
# pin on the epoch-less Samba revision shared by every binary.
cat > "$SAMBA_PIN" <<PIN
Package: src:samba
Pin: version *${SAMBA_DEB_VERSION#*:}
Pin-Priority: 1001
PIN
apt-get update -y
installed_version=$(dpkg-query -W -f='${Version}' samba 2>/dev/null || true)
if [[ "$installed_version" != "$SAMBA_DEB_VERSION" ]]; then
    # A fresh image may already carry a newer point release; the pin above
    # moves the whole family back, which apt treats as a downgrade.
    DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades \
        "samba=$SAMBA_DEB_VERSION"
fi

# Debian cloud images normally use deb822 sources. Add a temporary deb-src
# definition only when no source entry is already enabled.
if ! grep -RqsE '^(Types:.*[[:space:]]deb-src([[:space:]]|$)|deb-src[[:space:]])' \
    /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    DEB822_SOURCE=/etc/apt/sources.list.d/debian.sources
    [[ -r "$DEB822_SOURCE" && ! -e "$SOURCE_LIST" ]] || {
        echo "cannot derive deb-src entries from $DEB822_SOURCE" >&2
        exit 2
    }
    awk '
        /^Types:/ { print "Types: deb-src"; next }
        { print }
    ' "$DEB822_SOURCE" > "$SOURCE_LIST"
    SOURCE_LIST_CREATED=1
    apt-get update -y
fi

DEBIAN_FRONTEND=noninteractive apt-get build-dep -y \
    "samba=$SAMBA_DEB_VERSION"
(
    cd "$BUILD_ROOT"
    apt-get source "samba=$SAMBA_DEB_VERSION"
)

SAMBA_SOURCE=$(find "$BUILD_ROOT" -mindepth 1 -maxdepth 1 -type d \
    -name 'samba-*' -print -quit)
[[ -n "$SAMBA_SOURCE" ]] || { echo "downloaded Samba source directory not found" >&2; exit 3; }

install -m 0644 "$MODULE_SOURCE" \
    "$SAMBA_SOURCE/source3/modules/vfs_smbproxy_session.c"
cat >> "$SAMBA_SOURCE/source3/modules/wscript_build" <<'WAF'

bld.SAMBA3_MODULE('vfs_smbproxy_session',
                 subsystem='vfs',
                 source='vfs_smbproxy_session.c',
                 deps='samba-util',
                 init_function='vfs_smbproxy_session_init',
                 internal_module=False,
                 enabled=True)
WAF

MODULE_ROOT=$(smbd -b | awk -F': ' \
    '/MODULESDIR/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')
[[ "$MODULE_ROOT" == /* ]] || { echo "could not determine absolute Samba MODULESDIR" >&2; exit 4; }

(
    cd "$SAMBA_SOURCE"
    if grep -q '^configure:' debian/rules; then
        configure_target=configure
    elif grep -q '^override_dh_auto_configure:' debian/rules; then
        configure_target=override_dh_auto_configure
    else
        echo "Debian Samba configure target not found" >&2
        exit 4
    fi
    DEB_BUILD_OPTIONS='nocheck nodoc' ./debian/rules "$configure_target"
    PYTHONHASHSEED=1 ./buildtools/bin/waf build --targets=vfs_smbproxy_session
)

BUILT_MODULE=$(find "$SAMBA_SOURCE/bin" -type f \
    \( -name 'smbproxy_session.so' -o -name 'vfs_smbproxy_session.so' \
       -o -name 'libvfs_smbproxy_session.so' \
       -o -name 'libvfs_module_smbproxy_session.so' \) \
    -print -quit)
[[ -n "$BUILT_MODULE" ]] || { echo "built VFS module not found" >&2; exit 5; }

COMPONENT_VERSION=$(tr -d '[:space:]' < "$ROOT/VERSION")
SAMBA_VERSION_SUFFIX=${SAMBA_DEB_VERSION#*:}
SAMBA_VERSION_SUFFIX=$(printf '%s' "$SAMBA_VERSION_SUFFIX" \
    | sed 's/[^0-9A-Za-z.+~]/./g')
PACKAGE_VERSION="${COMPONENT_VERSION}+samba${SAMBA_VERSION_SUFFIX}"
PACKAGE_ARCH=$(dpkg --print-architecture)
PACKAGE_ROOT="$BUILD_ROOT/package"
PACKAGE_NAME="smbproxy-session-vfs_${PACKAGE_VERSION}_${PACKAGE_ARCH}.deb"

install -d -m 0755 \
    "$PACKAGE_ROOT/DEBIAN" \
    "$PACKAGE_ROOT$MODULE_ROOT/vfs" \
    "$PACKAGE_ROOT/usr/share/smbproxy-session-vfs"
install -m 0644 "$BUILT_MODULE" \
    "$PACKAGE_ROOT$MODULE_ROOT/vfs/smbproxy_session.so"
printf '%s\n' "$COMPONENT_VERSION" \
    > "$PACKAGE_ROOT/usr/share/smbproxy-session-vfs/component-version"
printf '%s\n' "$SAMBA_DEB_VERSION" \
    > "$PACKAGE_ROOT/usr/share/smbproxy-session-vfs/samba-package-version"
sha256sum "$MODULE_SOURCE" | awk '{ print $1 }' \
    > "$PACKAGE_ROOT/usr/share/smbproxy-session-vfs/source.sha256"

cat > "$PACKAGE_ROOT/DEBIAN/control" <<CONTROL
Package: smbproxy-session-vfs
Version: $PACKAGE_VERSION
Architecture: $PACKAGE_ARCH
Maintainer: Naimor, Inc. <admin@naimorinc.com>
Depends: samba (= $SAMBA_DEB_VERSION)
Built-Using: samba (= $SAMBA_DEB_VERSION)
Section: net
Priority: optional
Description: per-tree SMB1 session VFS module for the SMB proxy appliance
 This package is intentionally bound to one Debian Samba package revision.
CONTROL

install -d "$OUTPUT_DIR"
dpkg-deb --build --root-owner-group "$PACKAGE_ROOT" "$OUTPUT_DIR/$PACKAGE_NAME"
SOURCE_SHA256=$(sha256sum "$MODULE_SOURCE" | awk '{ print $1 }')
PACKAGE_SHA256=$(sha256sum "$OUTPUT_DIR/$PACKAGE_NAME" | awk '{ print $1 }')
cat > "$OUTPUT_DIR/$PACKAGE_NAME.manifest" <<MANIFEST
COMPONENT_VERSION=$COMPONENT_VERSION
SAMBA_DEB_VERSION=$SAMBA_DEB_VERSION
ARCHITECTURE=$PACKAGE_ARCH
MODULE_SOURCE_SHA256=$SOURCE_SHA256
PACKAGE_SHA256=$PACKAGE_SHA256
MANIFEST

restore_manual_marks
if [[ "${SMBPROXY_VFS_AUTOREMOVE:-0}" == "1" ]]; then
    DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
    apt-get clean
fi

echo "$OUTPUT_DIR/$PACKAGE_NAME"
