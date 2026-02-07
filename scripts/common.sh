#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FLUTTER_APP_DIR="${REPO_ROOT}/apps/flutter"
RENSDK_DIR="${REPO_ROOT}/Ren-SDK"

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

ensure_rensdk() {
  require_dir "${RENSDK_DIR}"
  [ -f "${RENSDK_DIR}/build.sh" ] || die "Missing ${RENSDK_DIR}/build.sh"
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

build_rensdk() {
  local platform="$1"
  ensure_rensdk
  log_info "==> Building Ren-SDK for ${platform}"
  run_in "${RENSDK_DIR}" ./build.sh "${platform}"
}

sync_rensdk_ios_xcframework() {
  ensure_flutter_app
  ensure_rensdk

  local src="${RENSDK_DIR}/target/RenSDK.xcframework"
  local dest="${FLUTTER_APP_DIR}/ios/RenSDK.xcframework"

  [ -d "$src" ] || die "Ren-SDK iOS artifact not found: ${src}"
  require_dir "${FLUTTER_APP_DIR}/ios"

  log_info "==> Sync RenSDK.xcframework -> ${dest}"
  rm -rf "${dest}"
  cp -R "${src}" "${dest}"
}

sync_rensdk_android_jnilibs() {
  ensure_flutter_app
  ensure_rensdk

  local src="${RENSDK_DIR}/target/android/jniLibs"
  local dest="${FLUTTER_APP_DIR}/android/app/src/main/jniLibs"

  [ -d "$src" ] || die "Ren-SDK Android artifact not found: ${src} (run Ren-SDK build.sh android)"
  require_dir "${FLUTTER_APP_DIR}/android/app/src/main"

  log_info "==> Sync Android jniLibs -> ${dest}"
  rm -rf "${dest}"
  mkdir -p "${dest}"
  cp -R "${src}/." "${dest}/"
}

sync_rensdk_windows_dll() {
  ensure_flutter_app
  ensure_rensdk

  local src1="${RENSDK_DIR}/pkg/windows/ren_sdk.dll"
  local src2="${RENSDK_DIR}/target/release/ren_sdk.dll"
  local dest="${FLUTTER_APP_DIR}/ren_sdk.dll"

  if [ -f "$src1" ]; then
    log_info "==> Sync ren_sdk.dll -> ${dest}"
    cp "$src1" "$dest"
  elif [ -f "$src2" ]; then
    log_info "==> Sync ren_sdk.dll -> ${dest}"
    cp "$src2" "$dest"
  else
    die "Ren-SDK Windows DLL not found: ${src1} or ${src2}"
  fi
}

sync_rensdk_linux_so() {
  ensure_flutter_app
  ensure_rensdk

  local src1="${RENSDK_DIR}/target/linux/libren_sdk.so"
  local src2="${RENSDK_DIR}/target/release/libren_sdk.so"
  local dest="${FLUTTER_APP_DIR}/libren_sdk.so"

  if [ -f "$src1" ]; then
    log_info "==> Sync libren_sdk.so -> ${dest}"
    cp "$src1" "$dest"
  elif [ -f "$src2" ]; then
    log_info "==> Sync libren_sdk.so -> ${dest}"
    cp "$src2" "$dest"
  else
    die "Ren-SDK Linux SO not found: ${src1} or ${src2}"
  fi
}

flutter_pub_get_if_needed() {
  ensure_flutter_app
  if [ ! -d "${FLUTTER_APP_DIR}/.dart_tool" ]; then
    log_info "==> flutter pub get"
    run_in "${FLUTTER_APP_DIR}" flutter pub get
  fi
}
