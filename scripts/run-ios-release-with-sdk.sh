#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RENSDK_DIR="${REPO_ROOT}/Ren-SDK"
BACKEND_DIR="${REPO_ROOT}/backend"
FLUTTER_DIR="${REPO_ROOT}/apps/flutter"
BACKEND_ENV_FILE="${BACKEND_DIR}/.env"
VERIFY_ENV_FILE="${BACKEND_DIR}/sdk-verification/current/SDK_FINGERPRINT_ALLOWLIST.env"
IOS_XC_LIB="${FLUTTER_DIR}/ios/RenSDK.xcframework/ios-arm64/libren_sdk.a"

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

upsert_env_key() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp="$(mktemp)"
  if [ -f "$file" ]; then
    awk -v k="$key" -v v="$value" '
      BEGIN { done=0 }
      $0 ~ ("^" k "=") {
        print k "=" v
        done=1
        next
      }
      { print }
      END {
        if (done==0) {
          print k "=" v
        }
      }
    ' "$file" > "$tmp"
  else
    printf '%s=%s\n' "$key" "$value" > "$tmp"
  fi
  mv "$tmp" "$file"
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
  require_cmd shasum
  require_cmd awk
  require_cmd grep

  [ -d "$RENSDK_DIR" ] || die "Ren-SDK directory not found: $RENSDK_DIR"
  [ -d "$FLUTTER_DIR" ] || die "Flutter directory not found: $FLUTTER_DIR"
  [ -d "$BACKEND_DIR" ] || die "Backend directory not found: $BACKEND_DIR"

  log "building Ren-SDK artifacts and verification bundle"
  (
    cd "$RENSDK_DIR"
    chmod +x ./build.sdk.sh
    if [ "${#SDK_BUILD_ARGS[@]}" -gt 0 ]; then
      ./build.sdk.sh "${SDK_BUILD_ARGS[@]}"
    else
      ./build.sdk.sh
    fi
  )

  [ -f "$VERIFY_ENV_FILE" ] || die "verification env file not found: $VERIFY_ENV_FILE"
  [ -f "$IOS_XC_LIB" ] || die "iOS SDK artifact not found: $IOS_XC_LIB"

  local allowlist_line allowlist_value ios_fingerprint
  allowlist_line="$(grep -E '^SDK_FINGERPRINT_ALLOWLIST=' "$VERIFY_ENV_FILE" | tail -n 1 || true)"
  [ -n "$allowlist_line" ] || die "SDK_FINGERPRINT_ALLOWLIST missing in $VERIFY_ENV_FILE"
  allowlist_value="${allowlist_line#SDK_FINGERPRINT_ALLOWLIST=}"
  [ -n "$allowlist_value" ] || die "SDK_FINGERPRINT_ALLOWLIST is empty"

  ios_fingerprint="$(shasum -a 256 "$IOS_XC_LIB" | awk '{print tolower($1)}')"
  [ -n "$ios_fingerprint" ] || die "failed to compute iOS SDK fingerprint"

  case ",$allowlist_value," in
    *",$ios_fingerprint,"*) ;;
    *)
      die "computed iOS fingerprint is not present in SDK_FINGERPRINT_ALLOWLIST"
      ;;
  esac

  if [ -f "$BACKEND_ENV_FILE" ]; then
    cp "$BACKEND_ENV_FILE" "${BACKEND_ENV_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  fi
  upsert_env_key "$BACKEND_ENV_FILE" "SDK_FINGERPRINT_ALLOWLIST" "$allowlist_value"
  log "updated backend/.env with SDK_FINGERPRINT_ALLOWLIST"

  log "running flutter pub get"
  (cd "$FLUTTER_DIR" && flutter pub get)

  local cmd
  cmd=(flutter run --release)
  if [ -n "$DEVICE_ID" ]; then
    cmd+=(-d "$DEVICE_ID")
  fi
  cmd+=(--dart-define="REN_IOS_SDK_FINGERPRINT=${ios_fingerprint}")
  cmd+=(--dart-define="REN_IOS_PRIVACY_OVERLAY=${IOS_PRIVACY_OVERLAY}")
  cmd+=(--dart-define="REN_IOS_ANTI_CAPTURE=${IOS_ANTI_CAPTURE}")
  if [ "${#EXTRA_ARGS[@]}" -gt 0 ]; then
    cmd+=("${EXTRA_ARGS[@]}")
  fi

  log "starting iOS release run with SDK fingerprint ${ios_fingerprint}"
  (
    cd "$FLUTTER_DIR"
    "${cmd[@]}"
  )
}

main "$@"
