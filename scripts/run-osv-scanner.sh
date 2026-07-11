#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

WORKDIR="${WORKING_DIRECTORY:?WORKING_DIRECTORY is required}"
REPORT_DIR="${REPORT_DIRECTORY:?REPORT_DIRECTORY is required}"
PROFILE="${PROFILE:-generic}"
OSV="$(security_tool osv-scanner)"
mkdir -p "$REPORT_DIR"

finish() {
  emit_output status "$1"
  emit_output findings "${2:-0}"
  emit_output blocking-findings "${3:-0}"
  emit_output json-path "${4:-}"
  emit_output sarif-path "${5:-}"
  exit 0
}

require_executable "$OSV" osv-scanner || finish scanner-execution-failure

SUPPORTED=()
MANIFEST_ONLY=false
case "$PROFILE" in
  php) CANDIDATES=(composer.lock) ;;
  rust) CANDIDATES=(Cargo.lock) ;;
  python)
    CANDIDATES=(requirements.txt poetry.lock Pipfile.lock pdm.lock pylock.toml uv.lock)
    [ -f "$WORKDIR/pyproject.toml" ] && MANIFEST_ONLY=true
    ;;
  typescript) CANDIDATES=(package-lock.json pnpm-lock.yaml yarn.lock) ;;
  generic)
    CANDIDATES=(composer.lock Cargo.lock requirements.txt poetry.lock Pipfile.lock pdm.lock pylock.toml uv.lock package-lock.json pnpm-lock.yaml yarn.lock)
    ;;
  *) finish scanner-execution-failure ;;
esac

for candidate in "${CANDIDATES[@]}"; do
  [ -f "$WORKDIR/$candidate" ] && SUPPORTED+=("$WORKDIR/$candidate")
done

if [ "${#SUPPORTED[@]}" -eq 0 ]; then
  if [ "$MANIFEST_ONLY" = true ]; then
    printf 'pyproject.toml is unresolved; it is not equivalent to a resolved dependency lock file.\n' >&2
    finish not-configured
  fi
  finish unsupported-repository
fi

ARGS=()
for path in "${SUPPORTED[@]}"; do
  ARGS+=(--lockfile "$path")
  case "$path" in
    */requirements.txt) printf 'Scanning requirements.txt; results depend on whether versions are fully pinned.\n' >&2 ;;
  esac
done

JSON_REPORT="$REPORT_DIR/osv-results.json"
SARIF_REPORT="$REPORT_DIR/osv-results.sarif"
JSON_LOG="$REPORT_DIR/osv-json.log"
SARIF_LOG="$REPORT_DIR/osv-sarif.log"
EMPTY_OSV_REPORT='{"results":[]}'
EMPTY_SARIF_REPORT='{"version":"2.1.0","runs":[]}'
set +e
"$OSV" scan source "${ARGS[@]}" --format json --output-file "$JSON_REPORT" >"$JSON_LOG" 2>&1
JSON_EXIT=$?
"$OSV" scan source "${ARGS[@]}" --format sarif --output-file "$SARIF_REPORT" >"$SARIF_LOG" 2>&1
SARIF_EXIT=$?
set -e

if [ "$JSON_EXIT" -eq 128 ] && grep -qF "No package sources found" "$JSON_LOG"; then
  JSON_EXIT=0
  printf '%s\n' "$EMPTY_OSV_REPORT" > "$JSON_REPORT"
fi
if [ "$SARIF_EXIT" -eq 128 ] && grep -qF "No package sources found" "$SARIF_LOG"; then
  SARIF_EXIT=0
  printf '%s\n' "$EMPTY_SARIF_REPORT" > "$SARIF_REPORT"
fi

if { [ "$JSON_EXIT" -ne 0 ] && [ "$JSON_EXIT" -ne 1 ]; } || \
   { [ "$SARIF_EXIT" -ne 0 ] && [ "$SARIF_EXIT" -ne 1 ]; }; then
  printf 'OSV-Scanner execution failed: json=%s sarif=%s\n' "$JSON_EXIT" "$SARIF_EXIT" >&2
  finish scanner-execution-failure 0 0 "$JSON_REPORT" "$SARIF_REPORT"
fi

if ! "$(security_python)" - "$JSON_REPORT" <<'PY'; then
import json
import sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
if not isinstance(data, dict) or not isinstance(data.get('results', []), list):
    raise SystemExit(1)
PY
  finish scanner-execution-failure 0 0 "$JSON_REPORT" "$SARIF_REPORT"
fi
if ! "$(security_python)" "$SCRIPT_DIR/validate-sarif.py" "$SARIF_REPORT"; then
  finish scanner-execution-failure 0 0 "$JSON_REPORT" "$SARIF_REPORT"
fi

FINDINGS="$("$(security_python)" - "$JSON_REPORT" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
identities = set()
for result in data.get('results', []):
    for item in result.get('packages', []):
        package = item.get('package', {})
        key = (package.get('ecosystem'), package.get('name'), package.get('version'))
        for vuln in item.get('vulnerabilities', []):
            identities.add((key, vuln.get('id')))
print(len(identities))
PY
)"

if [ "$FINDINGS" -gt 0 ]; then
  # OSV does not expose a reliable universal severity filter for every advisory.
  # It is the dependency authority, so all reported vulnerable packages block.
  finish findings-detected "$FINDINGS" "$FINDINGS" "$JSON_REPORT" "$SARIF_REPORT"
fi
finish passed 0 0 "$JSON_REPORT" "$SARIF_REPORT"
