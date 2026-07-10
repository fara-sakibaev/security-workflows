#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

WORKDIR="${WORKING_DIRECTORY:?WORKING_DIRECTORY is required}"
REPORT_DIR="${REPORT_DIRECTORY:?REPORT_DIRECTORY is required}"
INCLUDE_HISTORY="${INCLUDE_HISTORY:-true}"
GITLEAKS="$(security_tool gitleaks)"
CENTRAL_CONFIG="$SECURITY_ROOT/config/gitleaks/gitleaks.toml"
mkdir -p "$REPORT_DIR"

failure() {
  emit_output status scanner-execution-failure
  emit_output findings 0
  emit_output sarif-paths ""
  printf '%s\n' "$1" >&2
  exit 0
}

require_executable "$GITLEAKS" gitleaks || failure "Gitleaks installation failed."
[ -f "$CENTRAL_CONFIG" ] || failure "Central Gitleaks configuration is missing."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
EFFECTIVE_CONFIG="$TMP_DIR/gitleaks.toml"
cp "$CENTRAL_CONFIG" "$EFFECTIVE_CONFIG"

LOCAL_CONFIG="$WORKDIR/.security/gitleaks.toml"
if [ -e "$LOCAL_CONFIG" ]; then
  [ -s "$LOCAL_CONFIG" ] || failure "Project Gitleaks allowlist exists but is empty."
  "$(security_python)" - "$LOCAL_CONFIG" <<'PY' || failure "Project Gitleaks configuration must contain only additive [[allowlists]] entries."
import sys
import tomllib

with open(sys.argv[1], 'rb') as handle:
    data = tomllib.load(handle)
if set(data) != {'allowlists'} or not isinstance(data['allowlists'], list) or not data['allowlists']:
    raise SystemExit(1)
for entry in data['allowlists']:
    if not isinstance(entry, dict) or not entry.get('description'):
        raise SystemExit(1)
PY
  printf '\n' >> "$EFFECTIVE_CONFIG"
  cat "$LOCAL_CONFIG" >> "$EFFECTIVE_CONFIG"
fi

scan_and_count() {
  local mode="$1"
  local report="$2"
  local exit_code
  local findings
  set +e
  "$GITLEAKS" "$mode" "$WORKDIR" --config "$EFFECTIVE_CONFIG" --redact \
    --log-level warn --report-format sarif --report-path "$report"
  exit_code=$?
  set -e
  if [ ! -f "$report" ]; then
    printf '%s %s\n' "$exit_code" 0
    return
  fi
  if ! "$(security_python)" "$SCRIPT_DIR/validate-sarif.py" "$report"; then
    printf '%s %s\n' 127 0
    return
  fi
  findings="$("$(security_python)" - "$report" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
print(sum(len(run.get('results', [])) for run in data.get('runs', [])))
PY
)"
  printf '%s %s\n' "$exit_code" "$findings"
}

CONTENT_REPORT="$REPORT_DIR/gitleaks-content.sarif"
read -r CONTENT_EXIT CONTENT_FINDINGS < <(scan_and_count dir "$CONTENT_REPORT")
if { [ "$CONTENT_EXIT" -ne 0 ] && [ "$CONTENT_EXIT" -ne 1 ]; } || \
   { [ "$CONTENT_EXIT" -eq 1 ] && [ "$CONTENT_FINDINGS" -eq 0 ]; }; then
  failure "Gitleaks content scan failed with exit code $CONTENT_EXIT."
fi

HISTORY_FINDINGS=0
SARIF_PATHS="$CONTENT_REPORT"
if [ "$INCLUDE_HISTORY" = true ] && [ -d "$WORKDIR/.git" ]; then
  HISTORY_REPORT="$REPORT_DIR/gitleaks-history.sarif"
  read -r HISTORY_EXIT HISTORY_FINDINGS < <(scan_and_count git "$HISTORY_REPORT")
  if { [ "$HISTORY_EXIT" -ne 0 ] && [ "$HISTORY_EXIT" -ne 1 ]; } || \
     { [ "$HISTORY_EXIT" -eq 1 ] && [ "$HISTORY_FINDINGS" -eq 0 ]; }; then
    failure "Gitleaks history scan failed with exit code $HISTORY_EXIT."
  fi
  SARIF_PATHS="$SARIF_PATHS $HISTORY_REPORT"
elif [ "$INCLUDE_HISTORY" = true ]; then
  printf 'Git history scan not available because the caller checkout has no .git directory.\n' >&2
fi

TOTAL=$((CONTENT_FINDINGS + HISTORY_FINDINGS))
if [ "$TOTAL" -gt 0 ]; then
  emit_output status findings-detected
else
  emit_output status passed
fi
emit_output findings "$TOTAL"
emit_output sarif-paths "$SARIF_PATHS"
