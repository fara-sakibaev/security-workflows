#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

SHELLCHECK="$(security_tool shellcheck)"
ACTIONLINT="$(security_tool actionlint)"
require_executable "$SHELLCHECK" shellcheck
require_executable "$ACTIONLINT" actionlint

mapfile -t SHELL_FILES < <(find "$SECURITY_ROOT/scripts" -maxdepth 1 -type f -name '*.sh' -print | sort)
"$SHELLCHECK" "${SHELL_FILES[@]}"
"$ACTIONLINT" "$SECURITY_ROOT"/.github/workflows/*.yml
