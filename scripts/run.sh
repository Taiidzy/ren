#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run.sh <ios|macos|windows|linux> [options] [-- <extra flutter args>]

Options:
  --sdk              Build Ren-SDK before running
  --release          Run release build
  --debug            Run debug build (default)
  --device <id>      Pass -d <id> to flutter run
  -h, --help         Show this help

Examples:
  ./scripts/run.sh ios --sdk
  ./scripts/run.sh macos --device macos
  ./scripts/run.sh linux -- --verbose
EOF
}

platform="${1:-}"
if [ -z "$platform" ] || [ "$platform" = "-h" ] || [ "$platform" = "--help" ]; then
  usage
  exit 0
fi
shift || true

build_sdk=0
mode="debug"
device_id=""
extra_args=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sdk) build_sdk=1; shift ;;
    --release) mode="release"; shift ;;
    --debug) mode="debug"; shift ;;
    --device)
      device_id="${2:-}"
      [ -n "$device_id" ] || die "--device requires a device id"
      shift 2
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        extra_args+=("$1")
        shift
      done
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      extra_args+=("$1")
      shift
      ;;
  esac
done

ensure_flutter_app
flutter_pub_get_if_needed

if [ "$build_sdk" -eq 1 ]; then
  build_rensdk "$platform"
  if [ "$platform" = "ios" ]; then
    sync_rensdk_ios_xcframework
  fi
fi

host="$(host_os)"
case "$platform" in
  ios|macos)
    [ "$host" = "macos" ] || die "Running for '${platform}' requires macOS host"
    ;;
  windows)
    [ "$host" = "windows" ] || log_warn "Host is '${host}'. 'flutter run -d windows' usually requires Windows."
    ;;
  linux)
    [ "$host" = "linux" ] || log_warn "Host is '${host}'. 'flutter run -d linux' usually requires Linux."
    ;;
  *)
    usage
    die "Unknown platform: ${platform}"
    ;;
esac

args=("--${mode}")
if [ -n "$device_id" ]; then
  args+=("-d" "$device_id")
else
  case "$platform" in
    macos|windows|linux)
      args+=("-d" "$platform")
      ;;
    ios)
      ;;
  esac
fi

log_info "==> Flutter run (${platform}, ${mode})"
run_in "${FLUTTER_APP_DIR}" flutter run "${args[@]}" "${extra_args[@]}"