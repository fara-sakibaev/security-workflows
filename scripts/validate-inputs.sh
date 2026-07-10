#!/usr/bin/env bash
set -euo pipefail

PROFILE="${INPUT_PROFILE:?INPUT_PROFILE is required}"
SEVERITY="${INPUT_SEVERITY:-high}"
WORKDIR="${INPUT_WORKDIR:-.}"
SCAN_CONTAINER="${INPUT_SCAN_CONTAINER:-false}"
CONTAINER_IMAGE="${INPUT_CONTAINER_IMAGE:-}"

PROFILE="$(printf '%s' "$PROFILE" | tr '[:upper:]' '[:lower:]')"
case "$PROFILE" in
  generic|php|rust|python|typescript) ;;
  *) printf 'Unsupported profile: %s. Expected generic, php, rust, python, or typescript.\n' "$PROFILE" >&2; exit 2 ;;
esac

SEVERITY="$(printf '%s' "$SEVERITY" | tr '[:upper:]' '[:lower:]')"
case "$SEVERITY" in
  low|medium|high|critical) ;;
  *) printf 'Unsupported fail_on_severity: %s. Expected low, medium, high, or critical.\n' "$SEVERITY" >&2; exit 2 ;;
esac

case "$WORKDIR" in
  /*|*\\*) printf 'working_directory must be a relative POSIX path: %s\n' "$WORKDIR" >&2; exit 2 ;;
esac
if [[ "$WORKDIR" == *$'\n'* || "$WORKDIR" == *$'\r'* || "$WORKDIR" == *$'\t'* ]]; then
  printf 'working_directory cannot contain control characters.\n' >&2
  exit 2
fi
IFS='/' read -r -a parts <<< "$WORKDIR"
for part in "${parts[@]}"; do
  [ "$part" != ".." ] || { printf 'working_directory cannot contain .. path segments.\n' >&2; exit 2; }
done

case "$SCAN_CONTAINER" in true|false) ;; *) printf 'scan_container must be boolean.\n' >&2; exit 2 ;; esac
if [ "$SCAN_CONTAINER" = true ] && [ -z "$CONTAINER_IMAGE" ]; then
  printf 'container_image is required when scan_container is true.\n' >&2
  exit 2
fi
if [ -n "$CONTAINER_IMAGE" ] && [[ ! "$CONTAINER_IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._/:@+-]*$ ]]; then
  printf 'container_image contains unsupported characters.\n' >&2
  exit 2
fi

destination="${GITHUB_OUTPUT:-/dev/stdout}"
{
  printf 'profile=%s\n' "$PROFILE"
  printf 'severity=%s\n' "$SEVERITY"
  printf 'working-directory=%s\n' "$WORKDIR"
  printf 'container-image=%s\n' "$CONTAINER_IMAGE"
} >> "$destination"
