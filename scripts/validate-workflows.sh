#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
PYTHON_BIN="${PYTHON_BIN:-$(security_python)}"
ACTIONLINT="$(security_tool actionlint)"

require_executable "$PYTHON_BIN" python
require_executable "$ACTIONLINT" actionlint
"$PYTHON_BIN" -c 'import yaml' >/dev/null 2>&1 || {
  printf 'Required PyYAML module is unavailable. Run make bootstrap.\n' >&2
  exit 1
}

"$PYTHON_BIN" - "$REPO_DIR" <<'PY'
import pathlib
import re
import sys
import yaml

root = pathlib.Path(sys.argv[1]).resolve()
yaml_paths = sorted(root.glob('.github/workflows/*.yml')) + sorted(root.glob('actions/*/action.yml'))
if not yaml_paths:
    raise SystemExit('no workflows or action metadata found')
for path in yaml_paths:
    with path.open('r', encoding='utf-8') as handle:
        data = yaml.safe_load(handle)
    if not isinstance(data, dict):
        raise SystemExit(f'{path}: expected a YAML mapping')
    if path.name == 'action.yml':
        for key in ('name', 'description', 'runs'):
            if key not in data:
                raise SystemExit(f'{path}: missing {key}')
        if data['runs'].get('using') == 'composite':
            for output, definition in data.get('outputs', {}).items():
                if 'value' not in definition:
                    raise SystemExit(f'{path}: composite output {output} has no value mapping')

uses_pattern = re.compile(r'^\s*uses:\s*([^\s#]+)', re.MULTILINE)
sha_pattern = re.compile(r'^[0-9a-f]{40}$')
for path in sorted(root.glob('.github/workflows/*.yml')):
    text = path.read_text(encoding='utf-8')
    for reference in uses_pattern.findall(text):
        if reference.startswith('./'):
            local = reference
            if local.startswith('./security-platform/'):
                local = './' + local.removeprefix('./security-platform/')
            target = root / local.removeprefix('./')
            if target.is_dir():
                target = target / 'action.yml'
            if not target.exists():
                raise SystemExit(f'{path}: local uses target does not exist: {reference}')
            continue
        if '@' not in reference:
            raise SystemExit(f'{path}: external uses target has no ref: {reference}')
        ref = reference.rsplit('@', 1)[1]
        if not sha_pattern.fullmatch(ref):
            raise SystemExit(f'{path}: external action is not pinned to a full SHA: {reference}')
PY

for script_file in "$REPO_DIR"/scripts/*.sh; do
  if [ ! -x "$script_file" ]; then
    printf 'Non-executable script file: %s\n' "$script_file" >&2
    exit 1
  fi
done

"$ACTIONLINT" "$REPO_DIR"/.github/workflows/*.yml

UNSAFE_DL=$(rg -n "(curl[^|\n]*\|[[:space:]]*(sh|bash)|wget[^|\n]*\|[[:space:]]*(sh|bash)|\beval\b)" \
  "$REPO_DIR/.github/workflows" "$REPO_DIR/scripts" || true)
if [ -n "$UNSAFE_DL" ]; then
  printf 'Unsafe shell pattern detected:\n%s\n' "$UNSAFE_DL" >&2
  exit 1
fi

FORBIDDEN_PERMISSIONS=$(rg -n "(contents|actions|packages|pull-requests|id-token):[[:space:]]*write" \
  "$REPO_DIR/.github/workflows" || true)
if [ -n "$FORBIDDEN_PERMISSIONS" ]; then
  printf 'Forbidden workflow permissions detected:\n%s\n' "$FORBIDDEN_PERMISSIONS" >&2
  exit 1
fi

bash "$SCRIPT_DIR/validate-config.sh" "$REPO_DIR"
