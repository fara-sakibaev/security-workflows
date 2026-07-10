#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

WORKDIR="${WORKING_DIRECTORY:?WORKING_DIRECTORY is required}"
REPORT_DIR="${REPORT_DIRECTORY:?REPORT_DIRECTORY is required}"
FAIL_SEVERITY="${FAIL_ON_SEVERITY:-high}"
SCAN_CONTAINER="${SCAN_CONTAINER:-false}"
CONTAINER_IMAGE="${CONTAINER_IMAGE:-}"
TRIVY="$(security_tool trivy)"
CONFIG="$SECURITY_ROOT/config/trivy/trivy.yaml"
mkdir -p "$REPORT_DIR"

finish() {
  emit_output status "$1"
  emit_output vuln-findings "${2:-0}"
  emit_output misconfig-findings "${3:-0}"
  emit_output image-findings "${4:-0}"
  emit_output sarif-paths "${5:-}"
  exit 0
}

require_executable "$TRIVY" trivy || finish scanner-execution-failure
SEVERITIES="$(severity_list "$FAIL_SEVERITY")" || finish scanner-execution-failure
[ -f "$CONFIG" ] || finish scanner-execution-failure

count_results() {
  "$(security_python)" "$SCRIPT_DIR/validate-sarif.py" "$1" >/dev/null || return 1
  "$(security_python)" - "$1" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
print(sum(len(run.get('results', [])) for run in data.get('runs', [])))
PY
}

run_scan() {
  local report="$1"
  shift
  local exit_code
  set +e
  "$TRIVY" "$@" --config "$CONFIG" --severity "$SEVERITIES" --exit-code 1 \
    --format sarif --output "$report"
  exit_code=$?
  set -e
  if [ "$exit_code" -ne 0 ] && [ "$exit_code" -ne 1 ]; then
    return 127
  fi
  count_results "$report" || return 127
  return "$exit_code"
}

VULN_REPORT="$REPORT_DIR/trivy-vulnerabilities.sarif"
MISCONFIG_REPORT="$REPORT_DIR/trivy-misconfiguration.sarif"
set +e
VULN_FINDINGS="$(run_scan "$VULN_REPORT" fs "$WORKDIR" --scanners vuln)"; VULN_EXIT=$?
MISCONFIG_FINDINGS="$(run_scan "$MISCONFIG_REPORT" config "$WORKDIR")"; MISCONFIG_EXIT=$?
set -e
if [ "$VULN_EXIT" -eq 127 ] || [ "$MISCONFIG_EXIT" -eq 127 ]; then
  finish scanner-execution-failure 0 0 0 "$VULN_REPORT $MISCONFIG_REPORT"
fi

IMAGE_FINDINGS=0
IMAGE_EXIT=0
SARIF_PATHS="$VULN_REPORT $MISCONFIG_REPORT"
if [ "$SCAN_CONTAINER" = true ]; then
  [ -n "$CONTAINER_IMAGE" ] || finish scanner-execution-failure "$VULN_FINDINGS" "$MISCONFIG_FINDINGS" 0 "$SARIF_PATHS"
  IMAGE_REPORT="$REPORT_DIR/trivy-image.sarif"
  set +e
  IMAGE_FINDINGS="$(run_scan "$IMAGE_REPORT" image "$CONTAINER_IMAGE" --scanners vuln)"; IMAGE_EXIT=$?
  set -e
  [ "$IMAGE_EXIT" -ne 127 ] || finish scanner-execution-failure "$VULN_FINDINGS" "$MISCONFIG_FINDINGS" 0 "$SARIF_PATHS"
  SARIF_PATHS="$SARIF_PATHS $IMAGE_REPORT"
fi

if [ "$VULN_EXIT" -eq 1 ] || [ "$MISCONFIG_EXIT" -eq 1 ] || [ "$IMAGE_EXIT" -eq 1 ]; then
  finish findings-detected "$VULN_FINDINGS" "$MISCONFIG_FINDINGS" "$IMAGE_FINDINGS" "$SARIF_PATHS"
fi
finish passed "$VULN_FINDINGS" "$MISCONFIG_FINDINGS" "$IMAGE_FINDINGS" "$SARIF_PATHS"
