param()

$ErrorActionPreference = "Stop"

function Log([string]$Message) {
  Write-Host "[ren-sdk][Windows] $Message"
}

function Require-Command([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Missing required command: $Name"
  }
}

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$FlutterDir = Join-Path $RootDir "..\apps\flutter"
$AndroidOnly = if ([string]::IsNullOrWhiteSpace($env:SDK_BUILD_ANDROID_ONLY)) { "0" } else { $env:SDK_BUILD_ANDROID_ONLY }
$SkipFlutterSync = if ([string]::IsNullOrWhiteSpace($env:SDK_SKIP_FLUTTER_SYNC)) { "0" } else { $env:SDK_SKIP_FLUTTER_SYNC }
$BuiltAndroid = $false
$BuiltWindows = $false

function Ensure-Headers {
  if (-not (Get-Command cbindgen -ErrorAction SilentlyContinue)) {
    Log "cbindgen not found, installing..."
    cargo install cbindgen
  }
  cbindgen --config (Join-Path $RootDir "cbindgen.toml") --crate ren-sdk --output (Join-Path $RootDir "target\ren_sdk.h")
}

function Build-Android {
  Log "building Android (arm64-v8a, armeabi-v7a, x86, x86_64)"
  rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android
  cargo ndk --target aarch64-linux-android --platform 21 -- build --release --features ffi,crypto
  cargo ndk --target armv7-linux-androideabi --platform 21 -- build --release --features ffi,crypto
  cargo ndk --target i686-linux-android --platform 21 -- build --release --features ffi,crypto
  cargo ndk --target x86_64-linux-android --platform 21 -- build --release --features ffi,crypto

  New-Item -ItemType Directory -Force -Path (Join-Path $RootDir "target\android\jniLibs\arm64-v8a") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $RootDir "target\android\jniLibs\armeabi-v7a") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $RootDir "target\android\jniLibs\x86") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $RootDir "target\android\jniLibs\x86_64") | Out-Null

  Copy-Item (Join-Path $RootDir "target\aarch64-linux-android\release\libren_sdk.so") (Join-Path $RootDir "target\android\jniLibs\arm64-v8a\libren_sdk.so") -Force
  Copy-Item (Join-Path $RootDir "target\armv7-linux-androideabi\release\libren_sdk.so") (Join-Path $RootDir "target\android\jniLibs\armeabi-v7a\libren_sdk.so") -Force
  Copy-Item (Join-Path $RootDir "target\i686-linux-android\release\libren_sdk.so") (Join-Path $RootDir "target\android\jniLibs\x86\libren_sdk.so") -Force
  Copy-Item (Join-Path $RootDir "target\x86_64-linux-android\release\libren_sdk.so") (Join-Path $RootDir "target\android\jniLibs\x86_64\libren_sdk.so") -Force
  $script:BuiltAndroid = $true
}

function Build-Windows {
  Log "building Windows x86_64 dll"
  rustup target add x86_64-pc-windows-msvc
  cargo build --release --target x86_64-pc-windows-msvc --features ffi,crypto
  New-Item -ItemType Directory -Force -Path (Join-Path $RootDir "target\windows") | Out-Null
  Copy-Item (Join-Path $RootDir "target\x86_64-pc-windows-msvc\release\ren_sdk.dll") (Join-Path $RootDir "target\windows\ren_sdk.dll") -Force
  $script:BuiltWindows = $true
}

function Sync-ToFlutter {
  if ($SkipFlutterSync -eq "1") {
    Log "SDK_SKIP_FLUTTER_SYNC=1, skipping Flutter sync"
    return
  }
  if (-not $BuiltAndroid) {
    return
  }
  Log "syncing Android SDK to apps/flutter/android/app/src/main/jniLibs"
  $AndroidDst = Join-Path $FlutterDir "android\app\src\main\jniLibs"
  New-Item -ItemType Directory -Force -Path $AndroidDst | Out-Null
  foreach ($Abi in @("arm64-v8a", "armeabi-v7a", "x86", "x86_64")) {
    $DstAbi = Join-Path $AndroidDst $Abi
    if (Test-Path $DstAbi) { Remove-Item -Recurse -Force $DstAbi }
    Copy-Item (Join-Path $RootDir "target\android\jniLibs\$Abi") $DstAbi -Recurse -Force
  }
}

Require-Command "cargo"
Require-Command "rustup"
try {
  & cargo ndk -h | Out-Null
} catch {
  throw "cargo-ndk is required: cargo install cargo-ndk"
}

Ensure-Headers
Build-Android
if ($AndroidOnly -ne "1") {
  Build-Windows
} else {
  Log "SDK_BUILD_ANDROID_ONLY=1, skipping Windows build"
}
Sync-ToFlutter

Log "done"
