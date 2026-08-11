#!/usr/bin/env bash
# Fast local source/repository checks. The Debian compile is a separate,
# networked release gate because it downloads and configures Samba source.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

bash -n "$ROOT"/scripts/*.sh "$ROOT"/tests/*.sh
"$ROOT/tests/source-contract.sh"
"$ROOT/tests/repository-contract.sh"

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$ROOT"/scripts/*.sh "$ROOT"/tests/*.sh
fi

echo "all fast checks passed"
