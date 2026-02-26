#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RENSDK_DIR="${REPO_ROOT}/Ren-SDK"
BACKEND_DIR="${REPO_ROOT}/backend"
FLUTTER_DIR="${REPO_ROOT}/apps/flutter"

DEVICE_ID=""
EXTRA_ARGS=()
SDK_BUILD_ARGS=("--no-upload")

IOS_PRIVACY_OVERLAY="${REN_IOS_PRIVACY_OVERLAY:-false}"
IOS_ANTI_CAPTURE="${REN_IOS_ANTI_CAPTURE:-false}"

usage() {
  cat <<EOF
Usage:
  ./scripts/run-ios-release-with-sdk.sh [options] [-- <extra flutter run args>]

Options:
  --device <id>         iOS device/simulator id for flutter -d
  --allow-upload        allow remote upload from Ren-SDK build scripts
  -h, --help            show help

Environment:
  REN_IOS_PRIVACY_OVERLAY=true|false   (default: false)
  REN_IOS_ANTI_CAPTURE=true|false      (default: false)
EOF
}

log() { printf '[ios-release] %s\n' "$1"; }
die() { printf '[ios-release][error] %s\n' "$1" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --device)
        [ "${2:-}" != "" ] || die "--device requires value"
        DEVICE_ID="$2"
        shift 2
        ;;
      --allow-upload)
        SDK_BUILD_ARGS=()
        shift
        ;;
      --)
        shift
        EXTRA_ARGS=("$@")
        break
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  [ "$(uname -s)" = "Darwin" ] || die "this script supports macOS only"

  require_cmd flutter

  [ -d "$RENSDK_DIR" ] || die "Ren-SDK directory not found: $RENSDK_DIR"
  [ -d "$FLUTTER_DIR" ] || die "Flutter directory not found: $FLUTTER_DIR"
  [ -d "$BACKEND_DIR" ] || die "Backend directory not found: $BACKEND_DIR"

  log "building Ren-SDK artifacts"
  (
    cd "$RENSDK_DIR"
    chmod +x ./build.sdk.sh
    if [ "${#SDK_BUILD_ARGS[@]}" -gt 0 ]; then
      ./build.sdk.sh "${SDK_BUILD_ARGS[@]}"
    else
      ./build.sdk.sh
    fi
  )

  log "running flutter pub get"
  (cd "$FLUTTER_DIR" && flutter pub get)

  local cmd
  cmd=(flutter run --release)
  if [ -n "$DEVICE_ID" ]; then
    cmd+=(-d "$DEVICE_ID")
  fi
  cmd+=(--dart-define="REN_IOS_PRIVACY_OVERLAY=${IOS_PRIVACY_OVERLAY}")
  cmd+=(--dart-define="REN_IOS_ANTI_CAPTURE=${IOS_ANTI_CAPTURE}")
  if [ "${#EXTRA_ARGS[@]}" -gt 0 ]; then
    cmd+=("${EXTRA_ARGS[@]}")
  fi

  log "starting iOS release run"
  (
    cd "$FLUTTER_DIR"
    "${cmd[@]}"
  )
}

main "$@"
