#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FLUTTER_APP_DIR="${REPO_ROOT}/apps/flutter"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}$*${NC}"; }
log_warn() { echo -e "${YELLOW}$*${NC}"; }
log_err() { echo -e "${RED}$*${NC}" 1>&2; }

die() {
  log_err "$*"
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing dependency: '$1' (not found in PATH)"
}

require_dir() {
  [ -d "$1" ] || die "Missing directory: $1"
}

ensure_flutter_app() {
  require_cmd flutter
  require_dir "${FLUTTER_APP_DIR}"
}

host_os() {
  local u
  u="$(uname -s)"
  case "$u" in
    Darwin) echo "macos" ;;
    Linux) echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

run_in() {
  local dir="$1"
  shift
  (cd "$dir" && "$@")
}

flutter_pub_get_if_needed() {
  ensure_flutter_app
  if [ ! -d "${FLUTTER_APP_DIR}/.dart_tool" ]; then
    log_info "==> flutter pub get"
    run_in "${FLUTTER_APP_DIR}" flutter pub get
  fi
}
