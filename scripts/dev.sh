#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/dev.sh <ios|android|macos|windows|linux> [--release|--debug] [--device <id>] [-- <extra flutter args>]

Description:
  Builds Ren-SDK for the selected platform, syncs artifacts into the Flutter app,
  then runs the app via flutter.

Examples:
  ./scripts/dev.sh windows --debug
  ./scripts/dev.sh android --release
  ./scripts/dev.sh macos --device macos
  ./scripts/dev.sh linux -- --verbose
EOF
}

platform="${1:-}"
if [ -z "$platform" ] || [ "$platform" = "-h" ] || [ "$platform" = "--help" ]; then
  usage
  exit 0
fi
shift || true

mode="debug"
device_id=""
extra_args=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --release) mode="release"; shift ;;
    --debug) mode="debug"; shift ;;
    --device)
      device_id="${2:-}"
      [ -n "$device_id" ] || { echo "--device requires a device id" 1>&2; exit 1; }
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

args=("${platform}" --sdk "--${mode}")
if [ -n "$device_id" ]; then
  args+=(--device "$device_id")
fi

if [ "${#extra_args[@]}" -gt 0 ]; then
  args+=(-- "${extra_args[@]}")
fi

"${SCRIPT_DIR}/run.sh" "${args[@]}"
