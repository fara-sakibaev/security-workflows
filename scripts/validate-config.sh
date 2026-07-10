#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
PYTHON_BIN="${PYTHON_BIN:-$(security_python)}"
SEMGREP="${SEMGREP_BIN:-$SECURITY_ROOT/.tools/venv/bin/semgrep}"
TRIVY="$(security_tool trivy)"

require_executable "$PYTHON_BIN" python
require_executable "$SEMGREP" semgrep
require_executable "$TRIVY" trivy

"$PYTHON_BIN" -c 'import yaml' >/dev/null 2>&1 || {
  printf 'Required PyYAML module is unavailable. Run make bootstrap.\n' >&2
  exit 1
}

"$PYTHON_BIN" - "$REPO_DIR" <<'PY'
import pathlib
import sys
import yaml

root = pathlib.Path(sys.argv[1])
for path in (root / 'config' / 'trivy' / 'trivy.yaml', root / 'config' / 'semgrep' / 'common.yml'):
    if path.exists():
        with path.open('r', encoding='utf-8') as handle:
            yaml.safe_load(handle)

for path in (root / 'config' / 'semgrep').glob('*'):
    if path.suffix in {'.yml', '.yaml'}:
        with path.open('r', encoding='utf-8') as handle:
            yaml.safe_load(handle)
PY

for rule_file in "$REPO_DIR/config/semgrep"/*.yml; do
  "$SEMGREP" scan --validate --config "$rule_file"
done

"$TRIVY" --config "$REPO_DIR/config/trivy/trivy.yaml" --version >/dev/null
printf 'Configuration validation completed.\n'
