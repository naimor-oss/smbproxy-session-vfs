#!/usr/bin/env bash
# Verify exact-version packaging and the maintained Trixie tracking contract.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/scripts/build-debian-package.sh"
WORKFLOW="$ROOT/.github/workflows/trixie-samba.yml"
RELEASE_WORKFLOW="$ROOT/.github/workflows/publish-apt.yml"

# shellcheck disable=SC1091
source "$ROOT/compatibility/trixie.env"
[[ "$DEBIAN_SUITE" == "trixie" ]]
[[ "$SAMBA_DEB_VERSION" == *:*deb13* ]]
[[ -n "$TESTED_ARCHITECTURES" ]]

# shellcheck disable=SC2016
grep -qF 'Depends: samba (= $SAMBA_DEB_VERSION)' "$BUILD"
# shellcheck disable=SC2016
grep -qF './debian/rules "$configure_target"' "$BUILD"
grep -qF './buildtools/bin/waf build --targets=vfs_smbproxy_session' "$BUILD"
grep -qF 'samba-package-version' "$BUILD"
grep -qF 'schedule:' "$WORKFLOW"
grep -qF 'scripts/check-trixie-version.sh' "$WORKFLOW"
grep -qF 'scripts/build-debian-package.sh' "$WORKFLOW"
grep -qF 'scripts/build-apt-repository.sh' "$RELEASE_WORKFLOW"
grep -qF 'actions/deploy-pages@v4' "$RELEASE_WORKFLOW"

echo "repository contract passed"
