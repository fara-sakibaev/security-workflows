#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

GITLEAKS="$(security_tool gitleaks)"
OSV="$(security_tool osv-scanner)"
TRIVY="$(security_tool trivy)"
SEMGREP="$SECURITY_ROOT/.tools/venv/bin/semgrep"
require_executable "$GITLEAKS" gitleaks
require_executable "$OSV" osv-scanner
require_executable "$TRIVY" trivy
require_executable "$SEMGREP" semgrep

OUTPUT="$SECURITY_ROOT/.test-output/fixtures"
rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"

run_gitleaks_fixture() {
  local fixture="$1"
  local expected_exit="$2"
  local report="$3"
  local log="$4"
  local exit_code
  set +e
  "$GITLEAKS" dir "$fixture" --config "$SECURITY_ROOT/config/gitleaks/gitleaks.toml" \
    --redact --report-format sarif --report-path "$report" >"$log" 2>&1
  exit_code=$?
  set -e
  if [ "$exit_code" -ne "$expected_exit" ]; then
    printf 'Gitleaks fixture %s returned %s, expected %s\n' "$fixture" "$exit_code" "$expected_exit" >&2
    sed -n '1,120p' "$log" >&2
    exit 1
  fi
  "$(security_python)" "$SCRIPT_DIR/validate-sarif.py" "$report"
}

run_gitleaks_fixture "$SECURITY_ROOT/test-fixtures/clean-repo" 0 \
  "$OUTPUT/gitleaks-clean.sarif" "$OUTPUT/gitleaks-clean.log"
run_gitleaks_fixture "$SECURITY_ROOT/test-fixtures/fake-secret-repo" 1 \
  "$OUTPUT/gitleaks-finding.sarif" "$OUTPUT/gitleaks-finding.log"
if grep -Fq 'ghp_7F4kSyntheticCredentialForFixture000000' "$OUTPUT"/*.log; then
  printf 'Gitleaks log disclosed the complete synthetic credential.\n' >&2
  exit 1
fi

assert_output_status() {
  local file="$1"
  local expected="$2"
  if ! grep -Fxq "status=$expected" "$file"; then
    printf 'Expected status %s in %s.\n' "$expected" "$file" >&2
    sed -n '1,120p' "$file" >&2
    exit 1
  fi
}

: > "$OUTPUT/gitleaks-clean.outputs"
GITHUB_OUTPUT="$OUTPUT/gitleaks-clean.outputs" \
WORKING_DIRECTORY="$SECURITY_ROOT/test-fixtures/clean-repo" \
REPORT_DIRECTORY="$OUTPUT/gitleaks-clean-action" INCLUDE_HISTORY=false \
SECURITY_TOOLS_DIR="$(security_tools_dir)" bash "$SCRIPT_DIR/run-gitleaks.sh"
assert_output_status "$OUTPUT/gitleaks-clean.outputs" passed

: > "$OUTPUT/gitleaks-finding.outputs"
GITHUB_OUTPUT="$OUTPUT/gitleaks-finding.outputs" \
WORKING_DIRECTORY="$SECURITY_ROOT/test-fixtures/fake-secret-repo" \
REPORT_DIRECTORY="$OUTPUT/gitleaks-finding-action" INCLUDE_HISTORY=false \
SECURITY_TOOLS_DIR="$(security_tools_dir)" bash "$SCRIPT_DIR/run-gitleaks.sh"
assert_output_status "$OUTPUT/gitleaks-finding.outputs" findings-detected

"$SEMGREP" scan --validate --config "$SECURITY_ROOT/config/semgrep/common.yml"
"$SEMGREP" scan --validate --config "$SECURITY_ROOT/config/semgrep/php.yml"
set +e
"$SEMGREP" scan --error --config "$SECURITY_ROOT/config/semgrep/php.yml" \
  --json-output "$OUTPUT/semgrep-finding.json" \
  "$SECURITY_ROOT/test-fixtures/semgrep-finding" >/dev/null 2>&1
SEMGREP_EXIT=$?
set -e
[ "$SEMGREP_EXIT" -eq 1 ] || { printf 'Semgrep finding fixture did not return exit 1.\n' >&2; exit 1; }
"$(security_python)" - "$OUTPUT/semgrep-finding.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
ids = [result['check_id'].split('.')[-1] for result in data.get('results', [])]
if ids != ['php-exec-shell-command']:
    raise SystemExit(f'unexpected Semgrep findings: {ids}')
PY

"$SEMGREP" scan --error --config "$SECURITY_ROOT/config/semgrep/common.yml" \
  --json-output "$OUTPUT/semgrep-clean.json" "$SECURITY_ROOT/test-fixtures/clean-repo"

"$SEMGREP" scan --error --config "$SECURITY_ROOT/config/semgrep/common.yml" \
  --config "$SECURITY_ROOT/test-fixtures/semgrep-local-additive/.security/semgrep/local.yml" \
  --json-output "$OUTPUT/semgrep-additive.json" "$SECURITY_ROOT/test-fixtures/semgrep-local-additive" || true
"$(security_python)" - "$OUTPUT/semgrep-additive.json" <<'PY'
import json
import sys
ids = {result['check_id'].split('.')[-1] for result in json.load(open(sys.argv[1], encoding='utf-8')).get('results', [])}
if not {'no-shell-command-with-shell-true', 'fixture-local-rule'} <= ids:
    raise SystemExit(f'central and local Semgrep rules were not both active: {ids}')
PY
"$SEMGREP" scan --error --config "$SECURITY_ROOT/config/semgrep/common.yml" \
  --json-output "$OUTPUT/semgrep-empty-local.json" "$SECURITY_ROOT/test-fixtures/semgrep-empty-local"
if "$SEMGREP" scan --validate --config "$SECURITY_ROOT/test-fixtures/semgrep-malformed/.security/semgrep/broken.yml"; then
  printf 'Malformed project-local Semgrep rule unexpectedly validated.\n' >&2
  exit 1
fi
: > "$OUTPUT/semgrep-malformed.outputs"
GITHUB_OUTPUT="$OUTPUT/semgrep-malformed.outputs" \
WORKING_DIRECTORY="$SECURITY_ROOT/test-fixtures/semgrep-malformed" \
REPORT_DIRECTORY="$OUTPUT/semgrep-malformed" PROFILE=python LOCAL_RULES=.security/semgrep \
SEMGREP_BIN="$SEMGREP" bash "$SCRIPT_DIR/run-semgrep.sh"
assert_output_status "$OUTPUT/semgrep-malformed.outputs" scanner-execution-failure

set +e
"$OSV" scan source --format=json --output-file="$OUTPUT/osv-vulnerable.json" \
  "$SECURITY_ROOT/test-fixtures/osv-vulnerable" >/dev/null 2>&1
OSV_EXIT=$?
set -e
[ "$OSV_EXIT" -eq 1 ] || { printf 'OSV vulnerable fixture did not return exit 1.\n' >&2; exit 1; }
"$(security_python)" - "$OUTPUT/osv-vulnerable.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
packages = []
ids = []
for result in data.get('results', []):
    for item in result.get('packages', []):
        package = item.get('package', {})
        packages.append(package.get('name'))
        for vuln in item.get('vulnerabilities', []):
            ids.append(vuln.get('id'))
if 'lodash' not in packages or not any(ids):
    raise SystemExit(f'expected vulnerable lodash result, packages={packages}, ids={ids}')
PY

set +e
"$OSV" scan source --format=json --output-file="$OUTPUT/osv-clean.json" \
  "$SECURITY_ROOT/test-fixtures/osv-clean" >"$OUTPUT/osv-clean.log" 2>&1
OSV_CLEAN_EXIT=$?
set -e
if [ "$OSV_CLEAN_EXIT" -eq 128 ]; then
  if ! grep -Fq "No package sources found" "$OUTPUT/osv-clean.log"; then
    printf 'OSV clean fixture returned exit 128 for unexpected reason.\n' >&2
    sed -n '1,120p' "$OUTPUT/osv-clean.log" >&2
    exit 1
  fi
elif [ "$OSV_CLEAN_EXIT" -ne 0 ]; then
  printf 'OSV clean fixture returned %s.\n' "$OSV_CLEAN_EXIT" >&2
  sed -n '1,120p' "$OUTPUT/osv-clean.log" >&2
  exit 1
fi

STATUS_OUTPUT="$OUTPUT/status.outputs"
: > "$STATUS_OUTPUT"
GITHUB_OUTPUT="$STATUS_OUTPUT" INPUT_PROFILE=unknown INPUT_SEVERITY=high INPUT_WORKDIR=. \
  INPUT_SCAN_CONTAINER=false INPUT_CONTAINER_IMAGE="" \
  bash "$SCRIPT_DIR/validate-inputs.sh" >/dev/null 2>&1 && {
    printf 'Invalid profile input unexpectedly passed.\n' >&2
    exit 1
  }
: > "$STATUS_OUTPUT"
GITHUB_OUTPUT="$STATUS_OUTPUT" WORKING_DIRECTORY="$SECURITY_ROOT/test-fixtures/unsupported-stack" \
  REPORT_DIRECTORY="$OUTPUT/osv-unsupported" PROFILE=typescript \
  SECURITY_TOOLS_DIR="$(security_tools_dir)" bash "$SCRIPT_DIR/run-osv-scanner.sh"
grep -Fxq 'status=unsupported-repository' "$STATUS_OUTPUT" || {
  printf 'OSV unsupported repository status was not emitted.\n' >&2
  exit 1
}
: > "$STATUS_OUTPUT"
GITHUB_OUTPUT="$STATUS_OUTPUT" WORKING_DIRECTORY="$SECURITY_ROOT/test-fixtures/python-unresolved" \
  REPORT_DIRECTORY="$OUTPUT/osv-not-configured" PROFILE=python \
  SECURITY_TOOLS_DIR="$(security_tools_dir)" bash "$SCRIPT_DIR/run-osv-scanner.sh"
assert_output_status "$STATUS_OUTPUT" not-configured

: > "$STATUS_OUTPUT"
GITHUB_OUTPUT="$STATUS_OUTPUT" WORKING_DIRECTORY="$SECURITY_ROOT/test-fixtures/osv-vulnerable" \
  REPORT_DIRECTORY="$OUTPUT/osv-action-vulnerable" PROFILE=typescript \
  SECURITY_TOOLS_DIR="$(security_tools_dir)" bash "$SCRIPT_DIR/run-osv-scanner.sh"
assert_output_status "$STATUS_OUTPUT" findings-detected

: > "$STATUS_OUTPUT"
GITHUB_OUTPUT="$STATUS_OUTPUT" WORKING_DIRECTORY="$SECURITY_ROOT/test-fixtures/osv-clean" \
  REPORT_DIRECTORY="$OUTPUT/osv-action-clean" PROFILE=typescript \
  SECURITY_TOOLS_DIR="$(security_tools_dir)" bash "$SCRIPT_DIR/run-osv-scanner.sh"
assert_output_status "$STATUS_OUTPUT" passed

BANDIT_EXIT=0
"$SECURITY_ROOT/.tools/venv/bin/bandit" -r "$SECURITY_ROOT/test-fixtures/python" \
  -f json -o "$OUTPUT/bandit.json" >/dev/null 2>&1 || BANDIT_EXIT=$?
[ "$BANDIT_EXIT" -eq 1 ] || { printf 'Bandit fixture did not produce a finding.\n' >&2; exit 1; }

if command -v cargo >/dev/null 2>&1; then
  cargo clippy --manifest-path "$SECURITY_ROOT/test-fixtures/rust/Cargo.toml" --all-targets
  CARGO_DENY="$(security_tool cargo-deny)"
  require_executable "$CARGO_DENY" cargo-deny
  "$CARGO_DENY" --manifest-path "$SECURITY_ROOT/test-fixtures/rust/Cargo.toml" \
    check --config "$SECURITY_ROOT/test-fixtures/rust/deny.toml" bans licenses sources
  if [ -f "$SECURITY_ROOT/test-fixtures/rust-no-deny/deny.toml" ]; then
    printf 'Rust no-deny fixture unexpectedly contains cargo-deny policy.\n' >&2
    exit 1
  fi
else
  printf 'Required Rust fixture dependency is missing: cargo.\n' >&2
  exit 1
fi

TS_EXIT=0
"$SEMGREP" scan --error --config "$SECURITY_ROOT/config/semgrep/typescript.yml" \
  --json-output "$OUTPUT/semgrep-typescript.json" "$SECURITY_ROOT/test-fixtures/typescript" >/dev/null 2>&1 || TS_EXIT=$?
[ "$TS_EXIT" -eq 1 ] || { printf 'TypeScript Semgrep fixture did not produce a finding.\n' >&2; exit 1; }

if ! command -v composer >/dev/null 2>&1; then
  printf 'Required PHP fixture dependency is missing: composer.\n' >&2
  exit 1
fi
PHP_FIXTURE="$(mktemp -d)"
trap 'rm -rf "$PHP_FIXTURE"' EXIT
cp -R "$SECURITY_ROOT/test-fixtures/php/." "$PHP_FIXTURE/"
composer update --working-dir "$PHP_FIXTURE" --no-interaction --no-progress \
  --prefer-dist --no-scripts --no-plugins
[ -x "$PHP_FIXTURE/vendor/bin/psalm" ] || { printf 'Composer did not install project-local Psalm.\n' >&2; exit 1; }
set +e
(cd "$PHP_FIXTURE" && vendor/bin/psalm --no-progress --output-format=json --config=psalm.xml) \
  > "$OUTPUT/psalm.json"
PSALM_EXIT=$?
(cd "$PHP_FIXTURE" && vendor/bin/psalm --no-progress --taint-analysis \
  --output-format=json --config=psalm.xml) > "$OUTPUT/psalm-taint.json"
PSALM_TAINT_EXIT=$?
set -e
case "$PSALM_EXIT" in 0|2) ;; *) printf 'Psalm execution failed with %s.\n' "$PSALM_EXIT" >&2; exit 1 ;; esac
[ "$PSALM_TAINT_EXIT" -eq 2 ] || { printf 'Psalm taint fixture did not produce a finding.\n' >&2; exit 1; }
printf '<psalm>' > "$PHP_FIXTURE/psalm.xml"
set +e
(cd "$PHP_FIXTURE" && vendor/bin/psalm --no-progress --output-format=json --config=psalm.xml) >/dev/null 2>&1
INVALID_PSALM_EXIT=$?
set -e
[ "$INVALID_PSALM_EXIT" -eq 1 ] || { printf 'Invalid Psalm configuration was not classified as execution failure.\n' >&2; exit 1; }

if [ "${RUN_CONTAINER_TESTS:-false}" = true ]; then
  set +e
  "$TRIVY" image 'alpine@sha256:4bcff63911fcb4448bd4fdacec207030997caf25e9bea4045fa6c8c44de311d1' \
    --scanners vuln --severity HIGH,CRITICAL --exit-code 1 --format sarif \
    --output "$OUTPUT/trivy-image.sarif" >/dev/null 2>&1
  CONTAINER_EXIT=$?
  set -e
  case "$CONTAINER_EXIT" in 0|1) ;; *) printf 'Trivy pinned image fixture failed operationally.\n' >&2; exit 1 ;; esac
  "$(security_python)" "$SCRIPT_DIR/validate-sarif.py" "$OUTPUT/trivy-image.sarif"
else
  printf 'Optional container fixture skipped; set RUN_CONTAINER_TESTS=true to execute it.\n'
fi

set +e
"$TRIVY" config "$SECURITY_ROOT/test-fixtures/trivy-misconfiguration" \
  --severity HIGH,CRITICAL --exit-code 1 --format sarif \
  --output "$OUTPUT/trivy-misconfiguration.sarif" >/dev/null 2>&1
TRIVY_EXIT=$?
set -e
[ "$TRIVY_EXIT" -eq 1 ] || { printf 'Trivy misconfiguration fixture did not return exit 1.\n' >&2; exit 1; }
"$(security_python)" "$SCRIPT_DIR/validate-sarif.py" "$OUTPUT/trivy-misconfiguration.sarif"

: > "$STATUS_OUTPUT"
GITHUB_OUTPUT="$STATUS_OUTPUT" WORKING_DIRECTORY="$SECURITY_ROOT/test-fixtures/trivy-misconfiguration" \
  REPORT_DIRECTORY="$OUTPUT/trivy-action" FAIL_ON_SEVERITY=high SCAN_CONTAINER=false CONTAINER_IMAGE="" \
  SECURITY_TOOLS_DIR="$(security_tools_dir)" bash "$SCRIPT_DIR/run-trivy.sh"
assert_output_status "$STATUS_OUTPUT" findings-detected

printf 'Scanner fixture tests completed.\n'
