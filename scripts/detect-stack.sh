#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${1:-.}"
STACK="generic"

if [ -f "$REPO_DIR/composer.lock" ] || [ -f "$REPO_DIR/composer.json" ]; then
  STACK="php"
elif [ -f "$REPO_DIR/Cargo.lock" ] || [ -f "$REPO_DIR/Cargo.toml" ]; then
  STACK="rust"
elif [ -f "$REPO_DIR/requirements.txt" ] || [ -f "$REPO_DIR/pyproject.toml" ] || [ -f "$REPO_DIR/Pipfile.lock" ] || [ -f "$REPO_DIR/poetry.lock" ] || [ -f "$REPO_DIR/pdm.lock" ] || [ -f "$REPO_DIR/uv.lock" ] || compgen -G "$REPO_DIR/pylock.*.toml" >/dev/null; then
  STACK="python"
elif [ -f "$REPO_DIR/package-lock.json" ] || [ -f "$REPO_DIR/pnpm-lock.yaml" ] || [ -f "$REPO_DIR/yarn.lock" ] || [ -f "$REPO_DIR/package.json" ]; then
  STACK="typescript"
fi

echo "$STACK"
