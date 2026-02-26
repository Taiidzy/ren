#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_FLUTTER_DIR="${ROOT_DIR}/../apps/flutter"
ANDROID_ONLY="${SDK_BUILD_ANDROID_ONLY:-0}"
SKIP_FLUTTER_SYNC="${SDK_SKIP_FLUTTER_SYNC:-0}"
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
    log 'SDK_SKIP_FLUTTER_SYNC=1, skipping Flutter sync'
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

main() {
  require_cmd cargo
  require_cmd rustup
  require_cmd xcodebuild
  require_cmd lipo

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

  log 'done'
}

main "$@"
