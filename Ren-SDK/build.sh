#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Ren SDK Build Script ===${NC}\n"

# ============================================================================
# Сборка для iOS (Swift)
# ============================================================================
build_ios() {
    set -e

    echo -e "${YELLOW}Building for iOS (XCFramework)...${NC}"

    mkdir -p target/ios-headers
    cp target/ren_sdk.h target/ios-headers/ren_sdk.h

    rustup target add \
        aarch64-apple-ios \
        aarch64-apple-ios-sim \
        x86_64-apple-ios

    # --------------------------
    # Build libraries
    # --------------------------
    cargo build --release --target aarch64-apple-ios --features ffi,crypto
    cargo build --release --target aarch64-apple-ios-sim --features ffi,crypto
    cargo build --release --target x86_64-apple-ios --features ffi,crypto

    # --------------------------
    # Merge simulator libs
    # --------------------------
    mkdir -p target/ios-sim

    lipo -create \
        target/aarch64-apple-ios-sim/release/libren_sdk.a \
        target/x86_64-apple-ios/release/libren_sdk.a \
        -output target/ios-sim/libren_sdk.a

    # --------------------------
    # Create XCFramework
    # --------------------------
    rm -rf target/RenSDK.xcframework

    xcodebuild -create-xcframework \
        -library target/aarch64-apple-ios/release/libren_sdk.a \
        -headers target/ios-headers \
        -library target/ios-sim/libren_sdk.a \
        -headers target/ios-headers \
        -output target/RenSDK.xcframework

    echo -e "${GREEN}✓ iOS XCFramework created cleanly${NC}\n"
}



# ============================================================================
# Сборка для Android (JNI)
# ============================================================================
build_android() {
    echo -e "${YELLOW}Building for Android...${NC}"
    
    # Устанавливаем таргеты если не установлены
    rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android
    
    # Сборка для всех архитектур Android
    cargo ndk --target aarch64-linux-android --platform 21 -- build --release --features ffi,crypto
    cargo ndk --target armv7-linux-androideabi --platform 21 -- build --release --features ffi,crypto
    cargo ndk --target i686-linux-android --platform 21 -- build --release --features ffi,crypto
    cargo ndk --target x86_64-linux-android --platform 21 -- build --release --features ffi,crypto
    
    # Копируем библиотеки в правильную структуру для Android
    mkdir -p target/android/jniLibs/{arm64-v8a,armeabi-v7a,x86,x86_64}
    
    cp target/aarch64-linux-android/release/libren_sdk.so target/android/jniLibs/arm64-v8a/
    cp target/armv7-linux-androideabi/release/libren_sdk.so target/android/jniLibs/armeabi-v7a/
    cp target/i686-linux-android/release/libren_sdk.so target/android/jniLibs/x86/
    cp target/x86_64-linux-android/release/libren_sdk.so target/android/jniLibs/x86_64/
    
    echo -e "${GREEN}✓ Android build complete${NC}\n"
}

# ============================================================================
# Сборка для Linux (C#, general)
# ============================================================================
build_linux() {
    echo -e "${YELLOW}Building for Linux...${NC}"
    
    cargo build --release --features ffi,crypto
    
    mkdir -p target/linux
    cp target/release/libren_sdk.so target/linux/
    
    echo -e "${GREEN}✓ Linux build complete${NC}\n"
}

# ============================================================================
# Сборка для Windows (C#)
# ============================================================================
build_windows() {
    echo -e "${YELLOW}Building for Windows...${NC}"
    
    cargo build --release --features ffi,crypto
    
    mkdir -p pkg/windows
    cp target/x86_64-pc-windows-gnu/release/ren_sdk.dll pkg/windows/
    
    echo -e "${GREEN}✓ Windows build complete${NC}\n"
}

# ============================================================================
# Сборка для macOS
# ============================================================================
build_macos() {
    echo -e "${YELLOW}Building for macOS (universal dylib)...${NC}"

    # Проверяем таргеты
    rustup target add x86_64-apple-darwin aarch64-apple-darwin

    # Собираем для Intel
    cargo build --release --target x86_64-apple-darwin --features ffi,crypto --no-default-features

    # Собираем для Apple Silicon
    cargo build --release --target aarch64-apple-darwin --features ffi,crypto --no-default-features

    # Создаём universal dylib
    mkdir -p target/macos
    lipo -create \
        target/x86_64-apple-darwin/release/libren_sdk.dylib \
        target/aarch64-apple-darwin/release/libren_sdk.dylib \
        -output target/macos/libren_sdk.dylib

    # Проверяем архитектуры
    lipo -info target/macos/libren_sdk.dylib

    echo -e "${GREEN}✓ macOS universal dylib built at target/macos/libren_sdk.dylib${NC}\n"
}


# ============================================================================
# Сборка WASM для Web (TypeScript/React)
# ============================================================================
build_wasm() {
    echo -e "${YELLOW}Building WASM for Web...${NC}"
    
    # Проверяем установлен ли wasm-pack
    if ! command -v wasm-pack &> /dev/null; then
        echo "Installing wasm-pack..."
        cargo install wasm-pack
    fi
    
    # Сборка WASM с оптимизацией
    wasm-pack build --target web --out-dir pkg/web --features wasm,crypto --no-default-features
    wasm-pack build --target bundler --out-dir pkg/bundler --features wasm,crypto --no-default-features
    wasm-pack build --target nodejs --out-dir pkg/node --features wasm,crypto --no-default-features
    
    echo -e "${GREEN}✓ WASM build complete${NC}\n"
    echo -e "WASM packages created in:"
    echo -e "  - pkg/web (for vanilla JS/HTML)"
    echo -e "  - pkg/bundler (for Webpack/Rollup/Vite)"
    echo -e "  - pkg/node (for Node.js)"
}

# ============================================================================
# Генерация C header файла
# ============================================================================
generate_headers() {
    echo -e "${YELLOW}Generating C headers...${NC}"
    
    if ! command -v cbindgen &> /dev/null; then
        echo "Installing cbindgen..."
        cargo install cbindgen
    fi
    
    cbindgen --config cbindgen.toml --crate ren-sdk --output target/ren_sdk.h
    
    echo -e "${GREEN}✓ Header generated: target/ren_sdk.h${NC}\n"
}

# ============================================================================
# Main
# ============================================================================

case "$1" in
    ios)
        generate_headers
        build_ios
        ;;
    android)
        build_android
        generate_headers
        ;;
    linux)
        build_linux
        generate_headers
        ;;
    windows)
        build_windows
        generate_headers
        ;;
    macos)
        generate_headers
        build_macos
        ;;
    wasm)
        build_wasm
        ;;
    all)
        build_ios
        build_android
        build_linux
        build_macos
        build_wasm
        generate_headers
        ;;
    *)
        echo "Usage: $0 {ios|android|linux|windows|macos|wasm|all}"
        echo ""
        echo "Examples:"
        echo "  ./build.sh ios       - Build for iOS/Swift"
        echo "  ./build.sh android   - Build for Android/Kotlin"
        echo "  ./build.sh wasm      - Build for Web/TypeScript"
        echo "  ./build.sh all       - Build for all platforms"
        exit 1
        ;;
esac

echo -e "${GREEN}=== Build Complete ===${NC}"