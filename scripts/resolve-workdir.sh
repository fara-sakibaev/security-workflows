#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="${1:?workspace root is required}"
REQUESTED="${2:-.}"

case "$REQUESTED" in
  /*|*\\*) printf 'working_directory must be a relative POSIX path: %s\n' "$REQUESTED" >&2; exit 2 ;;
esac

IFS='/' read -r -a PARTS <<< "$REQUESTED"
for part in "${PARTS[@]}"; do
  if [ "$part" = ".." ]; then
    printf 'working_directory cannot contain .. path segments: %s\n' "$REQUESTED" >&2
    exit 2
  fi
done

ROOT_REAL="$(cd "$WORKSPACE_ROOT" && pwd -P)"
TARGET_REAL="$(cd "$WORKSPACE_ROOT/$REQUESTED" 2>/dev/null && pwd -P)" || {
  printf 'working_directory does not exist: %s\n' "$REQUESTED" >&2
  exit 2
}

case "$TARGET_REAL/" in
  "$ROOT_REAL/"*) ;;
  *) printf 'working_directory resolves outside the caller checkout: %s\n' "$REQUESTED" >&2; exit 2 ;;
esac

printf '%s\n' "$TARGET_REAL"
