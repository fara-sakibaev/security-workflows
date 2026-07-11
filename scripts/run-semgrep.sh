#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
# shellcheck source=versions.env
source "$SCRIPT_DIR/versions.env"

WORKDIR="${WORKING_DIRECTORY:?WORKING_DIRECTORY is required}"
PROFILE="${PROFILE:-generic}"
REPORT_DIR="${REPORT_DIRECTORY:?REPORT_DIRECTORY is required}"
LOCAL_RULES="${LOCAL_RULES:-.security/semgrep}"
mkdir -p "$REPORT_DIR"

finish() {
  emit_output status "$1"
  emit_output findings "${2:-0}"
  emit_output json-path "${3:-}"
  emit_output sarif-path "${4:-}"
  exit 0
}

SEMGREP="${SEMGREP_BIN:-$(security_tool semgrep)}"
if [ -n "${SEMGREP_BIN+x}" ]; then
  if ! "$SEMGREP" --version >/dev/null 2>&1; then
    finish scanner-execution-failure
  fi
else
  if [ -x "$SEMGREP" ] && "$SEMGREP" --version >/dev/null 2>&1; then
    :
  else
    VENV="${RUNNER_TEMP:-/tmp}/security-semgrep-$SEMGREP_VERSION"
    rm -rf "$VENV"
    if ! python3 -m venv "$VENV" || ! "$VENV/bin/python" -m pip install --disable-pip-version-check \
      "setuptools==$SETUPTOOLS_VERSION" "wheel" "semgrep==$SEMGREP_VERSION"; then
      finish scanner-execution-failure
    fi
    SEMGREP="$VENV/bin/semgrep"
  fi
fi

CONFIG_ARGS=(--config "$SECURITY_ROOT/config/semgrep/common.yml")
if [ "$PROFILE" != generic ]; then
  PROFILE_RULE="$SECURITY_ROOT/config/semgrep/$PROFILE.yml"
  [ -f "$PROFILE_RULE" ] || finish scanner-execution-failure
  CONFIG_ARGS+=(--config "$PROFILE_RULE")
fi

LOCAL_DIR="$WORKDIR/$LOCAL_RULES"
if [ -d "$LOCAL_DIR" ]; then
  while IFS= read -r -d '' rule; do
    if ! "$SEMGREP" scan --validate --config "$rule"; then
      finish scanner-execution-failure
    fi
    CONFIG_ARGS+=(--config "$rule")
  done < <(find "$LOCAL_DIR" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 | sort -z)
fi

JSON_REPORT="$REPORT_DIR/semgrep.json"
SARIF_REPORT="$REPORT_DIR/semgrep.sarif"
set +e
"$SEMGREP" scan --error "${CONFIG_ARGS[@]}" --json-output "$JSON_REPORT" \
  --sarif-output "$SARIF_REPORT" "$WORKDIR"
EXIT_CODE=$?
set -e
if [ "$EXIT_CODE" -ne 0 ] && [ "$EXIT_CODE" -ne 1 ]; then
  finish scanner-execution-failure 0 "$JSON_REPORT" "$SARIF_REPORT"
fi
if ! "$(security_python)" "$SCRIPT_DIR/validate-sarif.py" "$SARIF_REPORT"; then
  finish scanner-execution-failure 0 "$JSON_REPORT" "$SARIF_REPORT"
fi
FINDINGS="$("$(security_python)" - "$JSON_REPORT" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
print(len(data.get('results', [])))
PY
)" || finish scanner-execution-failure 0 "$JSON_REPORT" "$SARIF_REPORT"
if [ "$FINDINGS" -gt 0 ]; then
  finish findings-detected "$FINDINGS" "$JSON_REPORT" "$SARIF_REPORT"
fi
finish passed 0 "$JSON_REPORT" "$SARIF_REPORT"
