#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
# shellcheck source=scripts/versions.env
source "$SCRIPT_DIR/versions.env"

TOOL="${1:-}"
if [ -z "$TOOL" ]; then
  printf 'Usage: %s TOOL\n' "$0" >&2
  exit 2
fi

TOOLS_DIR="$(security_tools_dir)"
mkdir -p "$TOOLS_DIR"

case "$(uname -s)" in
  Linux) OS=linux ;;
  Darwin) OS=darwin ;;
  *) printf 'Unsupported operating system: %s\n' "$(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac

REPOSITORY=""
TAG=""
ASSET=""
BINARY="$TOOL"

case "$TOOL" in
  actionlint)
    REPOSITORY=rhysd/actionlint
    TAG="v$ACTIONLINT_VERSION"
    [ "$ARCH" = amd64 ] && ACTIONLINT_ARCH=x86_64 || ACTIONLINT_ARCH=arm64
    ASSET="actionlint_${ACTIONLINT_VERSION}_${OS}_${ACTIONLINT_ARCH}.tar.gz"
    ;;
  shellcheck)
    REPOSITORY=koalaman/shellcheck
    TAG="v$SHELLCHECK_VERSION"
    if [ "$ARCH" = amd64 ]; then SHELLCHECK_ARCH=x86_64; else SHELLCHECK_ARCH=aarch64; fi
    ASSET="shellcheck-v${SHELLCHECK_VERSION}.${OS}.${SHELLCHECK_ARCH}.tar.xz"
    ;;
  gitleaks)
    REPOSITORY=gitleaks/gitleaks
    TAG="v$GITLEAKS_VERSION"
    if [ "$ARCH" = amd64 ]; then GITLEAKS_ARCH=x64; else GITLEAKS_ARCH=arm64; fi
    ASSET="gitleaks_${GITLEAKS_VERSION}_${OS}_${GITLEAKS_ARCH}.tar.gz"
    ;;
  osv-scanner)
    REPOSITORY=google/osv-scanner
    TAG="v$OSV_SCANNER_VERSION"
    ASSET="osv-scanner_${OS}_${ARCH}"
    ;;
  trivy)
    REPOSITORY=aquasecurity/trivy
    TAG="v$TRIVY_VERSION"
    if [ "$OS" = linux ] && [ "$ARCH" = amd64 ]; then TRIVY_PLATFORM=Linux-64bit
    elif [ "$OS" = linux ]; then TRIVY_PLATFORM=Linux-ARM64
    elif [ "$ARCH" = amd64 ]; then TRIVY_PLATFORM=macOS-64bit
    else TRIVY_PLATFORM=macOS-ARM64
    fi
    ASSET="trivy_${TRIVY_VERSION}_${TRIVY_PLATFORM}.tar.gz"
    ;;
  *) printf 'Unsupported tool: %s\n' "$TOOL" >&2; exit 2 ;;
esac

DESTINATION="$TOOLS_DIR/$BINARY"
if [ -x "$DESTINATION" ]; then
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
RELEASE_JSON="$TMP_DIR/release.json"
ASSET_PATH="$TMP_DIR/$ASSET"
API_URL="https://api.github.com/repos/${REPOSITORY}/releases/tags/${TAG}"

curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
  "$API_URL" --output "$RELEASE_JSON"

readarray -t ASSET_METADATA < <("$(security_python)" - "$RELEASE_JSON" "$ASSET" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    release = json.load(handle)
matches = [asset for asset in release.get("assets", []) if asset.get("name") == sys.argv[2]]
if len(matches) != 1:
    raise SystemExit(f"expected one release asset named {sys.argv[2]!r}, found {len(matches)}")
asset = matches[0]
digest = asset.get("digest") or ""
if not digest.startswith("sha256:"):
    raise SystemExit(f"official SHA-256 digest is unavailable for {sys.argv[2]}")
print(asset["browser_download_url"])
print(digest.removeprefix("sha256:"))
PY
)

curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
  "${ASSET_METADATA[0]}" --output "$ASSET_PATH"

"$(security_python)" - "$ASSET_PATH" "${ASSET_METADATA[1]}" <<'PY'
import hashlib
import sys

digest = hashlib.sha256()
with open(sys.argv[1], "rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
if digest.hexdigest() != sys.argv[2]:
    raise SystemExit("downloaded asset SHA-256 does not match official release metadata")
PY

case "$ASSET" in
  *.tar.gz) tar -xzf "$ASSET_PATH" -C "$TMP_DIR" ;;
  *.tar.xz) tar -xJf "$ASSET_PATH" -C "$TMP_DIR" ;;
  *) chmod 0755 "$ASSET_PATH"; install -m 0755 "$ASSET_PATH" "$DESTINATION"; exit 0 ;;
esac

FOUND="$(find "$TMP_DIR" -type f -name "$BINARY" -perm -u+x -print -quit)"
if [ -z "$FOUND" ]; then
  printf 'Archive %s did not contain executable %s\n' "$ASSET" "$BINARY" >&2
  exit 1
fi
install -m 0755 "$FOUND" "$DESTINATION"
