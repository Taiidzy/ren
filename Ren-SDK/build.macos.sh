#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_FLUTTER_DIR="${ROOT_DIR}/../apps/flutter"
BACKEND_VERIFY_DIR_DEFAULT="${ROOT_DIR}/../backend/sdk-verification/current"
BACKEND_VERIFY_DIR="${SDK_VERIFY_LOCAL_DIR:-$BACKEND_VERIFY_DIR_DEFAULT}"
SCP_TARGET="${SDK_VERIFY_SCP_TARGET:-}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
VERIFY_PACKAGE_DIR="${ROOT_DIR}/target/sdk-verification/${STAMP}"
ANDROID_ONLY="${SDK_BUILD_ANDROID_ONLY:-0}"
SKIP_FLUTTER_SYNC="${SDK_SKIP_FLUTTER_SYNC:-0}"
SKIP_REMOTE_UPLOAD="${SDK_SKIP_REMOTE_UPLOAD:-0}"
BUILT_ANDROID=0
BUILT_IOS=0

log() {
  printf '[ren-sdk][macOS] %s\n' "$1"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "missing required command: $1"
    exit 1
  fi
}

ensure_headers() {
  if ! command -v cbindgen >/dev/null 2>&1; then
    log "cbindgen not found, installing..."
    cargo install cbindgen
  fi
  cbindgen --config "${ROOT_DIR}/cbindgen.toml" --crate ren-sdk --output "${ROOT_DIR}/target/ren_sdk.h"
}

build_android() {
  log 'building Android (arm64-v8a, armeabi-v7a, x86, x86_64)'
  rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android
  cargo ndk --target aarch64-linux-android --platform 21 -- build --release --features ffi,crypto
  cargo ndk --target armv7-linux-androideabi --platform 21 -- build --release --features ffi,crypto
  cargo ndk --target i686-linux-android --platform 21 -- build --release --features ffi,crypto
  cargo ndk --target x86_64-linux-android --platform 21 -- build --release --features ffi,crypto

  mkdir -p "${ROOT_DIR}/target/android/jniLibs/arm64-v8a" \
           "${ROOT_DIR}/target/android/jniLibs/armeabi-v7a" \
           "${ROOT_DIR}/target/android/jniLibs/x86" \
           "${ROOT_DIR}/target/android/jniLibs/x86_64"

  cp "${ROOT_DIR}/target/aarch64-linux-android/release/libren_sdk.so" "${ROOT_DIR}/target/android/jniLibs/arm64-v8a/libren_sdk.so"
  cp "${ROOT_DIR}/target/armv7-linux-androideabi/release/libren_sdk.so" "${ROOT_DIR}/target/android/jniLibs/armeabi-v7a/libren_sdk.so"
  cp "${ROOT_DIR}/target/i686-linux-android/release/libren_sdk.so" "${ROOT_DIR}/target/android/jniLibs/x86/libren_sdk.so"
  cp "${ROOT_DIR}/target/x86_64-linux-android/release/libren_sdk.so" "${ROOT_DIR}/target/android/jniLibs/x86_64/libren_sdk.so"
  BUILT_ANDROID=1
}

build_ios() {
  log 'building iOS XCFramework'
  rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios

  mkdir -p "${ROOT_DIR}/target/ios-headers"
  cp "${ROOT_DIR}/target/ren_sdk.h" "${ROOT_DIR}/target/ios-headers/ren_sdk.h"

  cargo build --release --target aarch64-apple-ios --features ffi,crypto
  cargo build --release --target aarch64-apple-ios-sim --features ffi,crypto
  cargo build --release --target x86_64-apple-ios --features ffi,crypto

  mkdir -p "${ROOT_DIR}/target/ios-sim"
  lipo -create \
    "${ROOT_DIR}/target/aarch64-apple-ios-sim/release/libren_sdk.a" \
    "${ROOT_DIR}/target/x86_64-apple-ios/release/libren_sdk.a" \
    -output "${ROOT_DIR}/target/ios-sim/libren_sdk.a"

  rm -rf "${ROOT_DIR}/target/RenSDK.xcframework"
  xcodebuild -create-xcframework \
    -library "${ROOT_DIR}/target/aarch64-apple-ios/release/libren_sdk.a" \
    -headers "${ROOT_DIR}/target/ios-headers" \
    -library "${ROOT_DIR}/target/ios-sim/libren_sdk.a" \
    -headers "${ROOT_DIR}/target/ios-headers" \
    -output "${ROOT_DIR}/target/RenSDK.xcframework"
  BUILT_IOS=1
}

sync_to_flutter() {
  if [[ "${SKIP_FLUTTER_SYNC}" == "1" ]]; then
    log 'SKIP_FLUTTER_SYNC=1, skipping Flutter sync'
    return
  fi
  if [[ "${BUILT_ANDROID}" == "1" ]]; then
    log 'syncing Android SDK to apps/flutter/android/app/src/main/jniLibs'
    mkdir -p "${APP_FLUTTER_DIR}/android/app/src/main/jniLibs"
    rm -rf "${APP_FLUTTER_DIR}/android/app/src/main/jniLibs/arm64-v8a" \
           "${APP_FLUTTER_DIR}/android/app/src/main/jniLibs/armeabi-v7a" \
           "${APP_FLUTTER_DIR}/android/app/src/main/jniLibs/x86" \
           "${APP_FLUTTER_DIR}/android/app/src/main/jniLibs/x86_64"
    cp -R "${ROOT_DIR}/target/android/jniLibs/." "${APP_FLUTTER_DIR}/android/app/src/main/jniLibs/"
  fi
  if [[ "${BUILT_IOS}" == "1" ]]; then
    log 'syncing iOS XCFramework to apps/flutter/ios/RenSDK.xcframework'
    rm -rf "${APP_FLUTTER_DIR}/ios/RenSDK.xcframework"
    cp -R "${ROOT_DIR}/target/RenSDK.xcframework" "${APP_FLUTTER_DIR}/ios/RenSDK.xcframework"
  fi
}

append_hash_line() {
  local abs="$1"
  local rel="$2"
  local hash
  hash="$(shasum -a 256 "$abs" | awk '{print $1}')"
  printf '%s  %s\n' "$hash" "$rel" >> "${VERIFY_PACKAGE_DIR}/SHA256SUMS.txt"
}

write_allowlist_file() {
  local values=()
  if [[ "${BUILT_ANDROID}" == "1" ]]; then
    values+=("$(shasum -a 256 "${ROOT_DIR}/target/android/jniLibs/arm64-v8a/libren_sdk.so" | awk '{print $1}')")
    values+=("$(shasum -a 256 "${ROOT_DIR}/target/android/jniLibs/armeabi-v7a/libren_sdk.so" | awk '{print $1}')")
    values+=("$(shasum -a 256 "${ROOT_DIR}/target/android/jniLibs/x86_64/libren_sdk.so" | awk '{print $1}')")
    values+=("$(shasum -a 256 "${ROOT_DIR}/target/android/jniLibs/x86/libren_sdk.so" | awk '{print $1}')")
  fi
  if [[ "${BUILT_IOS}" == "1" ]]; then
    values+=("$(shasum -a 256 "${ROOT_DIR}/target/RenSDK.xcframework/ios-arm64/libren_sdk.a" | awk '{print $1}')")
  fi

  {
    echo "# generated at ${STAMP}"
    echo "SDK_FINGERPRINT_ALLOWLIST=$(IFS=,; echo "${values[*]}")"
  } > "${VERIFY_PACKAGE_DIR}/SDK_FINGERPRINT_ALLOWLIST.env"
}

prepare_verification_package() {
  log "preparing verification package at ${VERIFY_PACKAGE_DIR}"
  mkdir -p "${VERIFY_PACKAGE_DIR}"
  if [[ "${BUILT_ANDROID}" == "1" ]]; then
    mkdir -p "${VERIFY_PACKAGE_DIR}/android/jniLibs"
    cp -R "${ROOT_DIR}/target/android/jniLibs/." "${VERIFY_PACKAGE_DIR}/android/jniLibs/"
  fi
  if [[ "${BUILT_IOS}" == "1" ]]; then
    mkdir -p "${VERIFY_PACKAGE_DIR}/ios"
    cp -R "${ROOT_DIR}/target/RenSDK.xcframework" "${VERIFY_PACKAGE_DIR}/ios/RenSDK.xcframework"
  fi
  cp "${ROOT_DIR}/target/ren_sdk.h" "${VERIFY_PACKAGE_DIR}/ren_sdk.h"

  : > "${VERIFY_PACKAGE_DIR}/SHA256SUMS.txt"
  while IFS= read -r -d '' file; do
    rel="${file#${VERIFY_PACKAGE_DIR}/}"
    append_hash_line "$file" "$rel"
  done < <(find "${VERIFY_PACKAGE_DIR}" -type f ! -name "SHA256SUMS.txt" -print0 | sort -z)

  write_allowlist_file
}

sync_to_backend_and_server() {
  log "syncing verification package to local backend path: ${BACKEND_VERIFY_DIR}"
  mkdir -p "${BACKEND_VERIFY_DIR}"
  rm -rf "${BACKEND_VERIFY_DIR:?}/"*
  cp -R "${VERIFY_PACKAGE_DIR}/." "${BACKEND_VERIFY_DIR}/"

  if [[ -n "${SCP_TARGET}" ]]; then
    if [[ "${SKIP_REMOTE_UPLOAD}" == "1" ]]; then
      log 'SKIP_REMOTE_UPLOAD=1, skipping remote upload'
      return
    fi
    require_cmd scp
    log "uploading verification package via scp to ${SCP_TARGET}"
    scp -r "${VERIFY_PACKAGE_DIR}" "${SCP_TARGET}"
  else
    log 'SDK_VERIFY_SCP_TARGET is empty, skipping remote upload'
  fi
}

main() {
  require_cmd cargo
  require_cmd rustup
  require_cmd xcodebuild
  require_cmd lipo
  require_cmd shasum
  require_cmd find
  require_cmd awk

  if ! command -v cargo-ndk >/dev/null 2>&1 && ! cargo ndk -h >/dev/null 2>&1; then
    log 'cargo-ndk is required: cargo install cargo-ndk'
    exit 1
  fi

  ensure_headers
  build_android
  if [[ "${ANDROID_ONLY}" != "1" ]]; then
    build_ios
  else
    log 'SDK_BUILD_ANDROID_ONLY=1, skipping iOS build'
  fi
  sync_to_flutter
  prepare_verification_package
  sync_to_backend_and_server

  log 'done'
}

main "$@"
