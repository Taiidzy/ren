#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/build.sh <ios|macos|windows|linux> [options] [-- <extra flutter args>]

Options:
  --sdk              Build Ren-SDK before building the app
  --release          Release build (default)
  --debug            Debug build
  --no-codesign      (iOS only) Build without code signing
  --ipa              (iOS only) Build IPA (uses flutter build ipa)
  --output <dir>     Copy resulting artifact(s) to this directory
  -h, --help         Show this help
EOF
}

platform="${1:-}"
if [ -z "$platform" ] || [ "$platform" = "-h" ] || [ "$platform" = "--help" ]; then
  usage
  exit 0
fi
shift || true

build_sdk=0
mode="release"
no_codesign=0
build_ipa=0
output_dir=""

extra_args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --sdk) build_sdk=1; shift ;;
    --release) mode="release"; shift ;;
    --debug) mode="debug"; shift ;;
    --no-codesign) no_codesign=1; shift ;;
    --ipa) build_ipa=1; shift ;;
    --output)
      output_dir="${2:-}"
      [ -n "$output_dir" ] || die "--output requires a directory"
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
    [ "$host" = "macos" ] || die "Building for '${platform}' requires macOS host"
    ;;
  windows)
    [ "$host" = "windows" ] || log_warn "Host is '${host}'. 'flutter build windows' usually requires Windows."
    ;;
  linux)
    [ "$host" = "linux" ] || log_warn "Host is '${host}'. 'flutter build linux' usually requires Linux."
    ;;
  *)
    usage
    die "Unknown platform: ${platform}"
    ;;
esac

log_info "==> Flutter build (${platform}, ${mode})"

mode_cap=""
case "$mode" in
  release) mode_cap="Release" ;;
  debug) mode_cap="Debug" ;;
  *) die "Unknown build mode: ${mode}" ;;
esac

case "$platform" in
  ios)
    if [ "$build_ipa" -eq 1 ]; then
      run_in "${FLUTTER_APP_DIR}" flutter build ipa --"${mode}" "${extra_args[@]}"
      artifact="${FLUTTER_APP_DIR}/build/ios/ipa"
    else
      args=("--${mode}")
      if [ "$no_codesign" -eq 1 ]; then
        args+=("--no-codesign")
      fi
      run_in "${FLUTTER_APP_DIR}" flutter build ios "${args[@]}" "${extra_args[@]}"
      artifact="${FLUTTER_APP_DIR}/build/ios/iphoneos"
    fi
    ;;
  macos)
    run_in "${FLUTTER_APP_DIR}" flutter build macos --"${mode}" "${extra_args[@]}"
    artifact="${FLUTTER_APP_DIR}/build/macos/Build/Products/${mode_cap}"
    ;;
  windows)
    run_in "${FLUTTER_APP_DIR}" flutter build windows --"${mode}" "${extra_args[@]}"
    artifact="${FLUTTER_APP_DIR}/build/windows/x64/runner/${mode_cap}"
    ;;
  linux)
    run_in "${FLUTTER_APP_DIR}" flutter build linux --"${mode}" "${extra_args[@]}"
    artifact="${FLUTTER_APP_DIR}/build/linux/x64/${mode}/bundle"
    ;;
esac

log_info "==> Artifact location: ${artifact}"

if [ -n "$output_dir" ]; then
  mkdir -p "$output_dir"
  log_info "==> Copying artifacts to: ${output_dir}"
  cp -R "${artifact}" "${output_dir}/" 2>/dev/null || cp -R "${artifact}" "${output_dir}" || true
fi
