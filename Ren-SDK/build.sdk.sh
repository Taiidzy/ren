#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ANDROID_ONLY=0
NO_UPLOAD=0
NO_SYNC_FLUTTER=0

usage() {
  cat <<EOF
Usage: ./build.sdk.sh [--android-only] [--no-upload] [--no-sync-flutter]

Flags:
  --android-only     Build only Android artifacts
  --no-upload        Skip remote upload (scp)
  --no-sync-flutter  Skip copying artifacts into apps/flutter
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --android-only) ANDROID_ONLY=1 ;;
    --no-upload) NO_UPLOAD=1 ;;
    --no-sync-flutter) NO_SYNC_FLUTTER=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "build.sdk.sh is for macOS. Use build.sdk.ps1 on Windows." >&2
  exit 1
fi

SDK_BUILD_ANDROID_ONLY="${ANDROID_ONLY}" \
SDK_SKIP_REMOTE_UPLOAD="${NO_UPLOAD}" \
SDK_SKIP_FLUTTER_SYNC="${NO_SYNC_FLUTTER}" \
"${ROOT_DIR}/build.macos.sh"
