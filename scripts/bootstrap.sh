#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
# shellcheck disable=SC1091
# shellcheck source=./versions.env
source "$SCRIPT_DIR/versions.env"

for tool in actionlint shellcheck gitleaks osv-scanner trivy; do
  "$SCRIPT_DIR/install-tool.sh" "$tool"
done

VENV="$SECURITY_ROOT/.tools/venv"
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/python" -m pip install --disable-pip-version-check --upgrade \
  "setuptools==$SETUPTOOLS_VERSION" \
  "wheel" \
  "PyYAML==$PYYAML_VERSION" \
  "semgrep==$SEMGREP_VERSION" \
  "bandit==$BANDIT_VERSION"

"$VENV/bin/python" -c 'import pkg_resources; print("setuptools OK")' \
  || {
    printf 'pkg_resources is unavailable after bootstrap; forcing setuptools reinstall.\n' >&2
    "$VENV/bin/python" -m pip install --disable-pip-version-check --force-reinstall \
      "setuptools==$SETUPTOOLS_VERSION" \
      "wheel"
    "$VENV/bin/python" -c 'import pkg_resources; print("setuptools OK")' \
      || { printf 'pkg_resources is still unavailable; aborting bootstrap.\n' >&2; exit 1; }
  }

if ! command -v cargo >/dev/null 2>&1; then
  printf 'cargo is required to prepare the pinned cargo-deny validator.\n' >&2
  exit 1
fi
if [ ! -x "$SECURITY_ROOT/.tools/bin/cargo-deny" ]; then
  cargo install --locked --root "$SECURITY_ROOT/.tools/cargo-deny" \
    --version "$CARGO_DENY_VERSION" cargo-deny
  ln -s ../cargo-deny/bin/cargo-deny "$SECURITY_ROOT/.tools/bin/cargo-deny"
fi

"$(security_tool actionlint)" -version
"$(security_tool shellcheck)" --version
"$(security_tool gitleaks)" version
"$(security_tool osv-scanner)" --version
"$(security_tool trivy)" --version
"$VENV/bin/semgrep" --version
"$VENV/bin/bandit" --version
"$SECURITY_ROOT/.tools/bin/cargo-deny" --version
"$VENV/bin/python" -c 'import yaml; print(yaml.__version__)'
