#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

TRIVY="$(security_tool trivy)"
SEMGREP="$SECURITY_ROOT/.tools/venv/bin/semgrep"
require_executable "$TRIVY" trivy
require_executable "$SEMGREP" semgrep

OUTPUT="$SECURITY_ROOT/.test-output/security"
rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"

GITHUB_OUTPUT="$OUTPUT/gitleaks.outputs" \
WORKING_DIRECTORY="$SECURITY_ROOT" \
REPORT_DIRECTORY="$OUTPUT/gitleaks" \
INCLUDE_HISTORY=true \
  bash "$SCRIPT_DIR/run-gitleaks.sh"
GITLEAKS_STATUS="$(sed -n 's/^status=//p' "$OUTPUT/gitleaks.outputs" | tail -n 1)"
[ "$GITLEAKS_STATUS" = passed ] || {
  printf 'Dogfood Gitleaks status: %s\n' "$GITLEAKS_STATUS" >&2
  exit 1
}
"$SEMGREP" scan --error --config "$SECURITY_ROOT/config/semgrep/common.yml" \
  --sarif-output "$OUTPUT/semgrep.sarif" "$SECURITY_ROOT"
"$TRIVY" fs "$SECURITY_ROOT" --config "$SECURITY_ROOT/config/trivy/trivy.yaml" \
  --scanners vuln --severity HIGH,CRITICAL --exit-code 1 --format sarif \
  --output "$OUTPUT/trivy-vulnerabilities.sarif"
"$TRIVY" config "$SECURITY_ROOT" --config "$SECURITY_ROOT/config/trivy/trivy.yaml" \
  --severity HIGH,CRITICAL --exit-code 1 --format sarif \
  --output "$OUTPUT/trivy-misconfiguration.sarif"
