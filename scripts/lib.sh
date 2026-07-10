#!/usr/bin/env bash
set -euo pipefail

SECURITY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

security_tools_dir() {
  printf '%s\n' "${SECURITY_TOOLS_DIR:-$SECURITY_ROOT/.tools/bin}"
}

security_python() {
  local candidate="${SECURITY_PYTHON:-$SECURITY_ROOT/.tools/venv/bin/python}"
  if [ -x "$candidate" ]; then
    printf '%s\n' "$candidate"
  elif command -v python3 >/dev/null 2>&1; then
    command -v python3
  else
    printf '%s\n' "python3"
  fi
}

security_tool() {
  local name="$1"
  local candidate
  candidate="$(security_tools_dir)/$name"
  if [ -x "$candidate" ]; then
    printf '%s\n' "$candidate"
  elif command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
  else
    printf '%s\n' "$candidate"
  fi
}

require_executable() {
  local path="$1"
  local label="$2"
  if [ ! -x "$path" ]; then
    printf 'Required tool is unavailable: %s (%s)\n' "$label" "$path" >&2
    printf 'Run make bootstrap before this command.\n' >&2
    return 1
  fi
}

emit_output() {
  local key="$1"
  local value="$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
  else
    printf '%s=%s\n' "$key" "$value"
  fi
}

severity_list() {
  local severity
  severity="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$severity" in
    low) printf '%s\n' 'LOW,MEDIUM,HIGH,CRITICAL' ;;
    medium) printf '%s\n' 'MEDIUM,HIGH,CRITICAL' ;;
    high) printf '%s\n' 'HIGH,CRITICAL' ;;
    critical) printf '%s\n' 'CRITICAL' ;;
    *) printf 'Invalid severity: %s\n' "$1" >&2; return 1 ;;
  esac
}
