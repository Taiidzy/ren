param(
  [string]$SdkVerifyScpTarget = $env:SDK_VERIFY_SCP_TARGET,
  [string]$SdkVerifyLocalDir = $env:SDK_VERIFY_LOCAL_DIR
)

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
if ([string]::IsNullOrWhiteSpace($SdkVerifyLocalDir)) {
  $SdkVerifyLocalDir = Join-Path $RootDir "..\backend\sdk-verification\current"
}
$Stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$VerifyPackageDir = Join-Path $RootDir "target\sdk-verification\$Stamp"
$AndroidOnly = if ([string]::IsNullOrWhiteSpace($env:SDK_BUILD_ANDROID_ONLY)) { "0" } else { $env:SDK_BUILD_ANDROID_ONLY }
$SkipFlutterSync = if ([string]::IsNullOrWhiteSpace($env:SDK_SKIP_FLUTTER_SYNC)) { "0" } else { $env:SDK_SKIP_FLUTTER_SYNC }
$SkipRemoteUpload = if ([string]::IsNullOrWhiteSpace($env:SDK_SKIP_REMOTE_UPLOAD)) { "0" } else { $env:SDK_SKIP_REMOTE_UPLOAD }
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

function Write-AllowlistFile {
  $values = New-Object System.Collections.Generic.List[string]
  if ($BuiltAndroid) {
    $values.Add((Get-FileHash (Join-Path $RootDir "target\android\jniLibs\arm64-v8a\libren_sdk.so") -Algorithm SHA256).Hash.ToLower())
    $values.Add((Get-FileHash (Join-Path $RootDir "target\android\jniLibs\armeabi-v7a\libren_sdk.so") -Algorithm SHA256).Hash.ToLower())
    $values.Add((Get-FileHash (Join-Path $RootDir "target\android\jniLibs\x86_64\libren_sdk.so") -Algorithm SHA256).Hash.ToLower())
    $values.Add((Get-FileHash (Join-Path $RootDir "target\android\jniLibs\x86\libren_sdk.so") -Algorithm SHA256).Hash.ToLower())
  }
  if ($BuiltWindows) {
    $values.Add((Get-FileHash (Join-Path $RootDir "target\windows\ren_sdk.dll") -Algorithm SHA256).Hash.ToLower())
  }
  $line = "SDK_FINGERPRINT_ALLOWLIST=$($values -join ',')"
  @(
    "# generated at $Stamp",
    $line
  ) | Set-Content -Path (Join-Path $VerifyPackageDir "SDK_FINGERPRINT_ALLOWLIST.env") -Encoding ascii
}

function Prepare-VerificationPackage {
  Log "preparing verification package at $VerifyPackageDir"
  New-Item -ItemType Directory -Force -Path $VerifyPackageDir | Out-Null

  if ($BuiltAndroid) {
    New-Item -ItemType Directory -Force -Path (Join-Path $VerifyPackageDir "android\jniLibs") | Out-Null
    Copy-Item (Join-Path $RootDir "target\android\jniLibs\*") (Join-Path $VerifyPackageDir "android\jniLibs") -Recurse -Force
  }
  if ($BuiltWindows) {
    New-Item -ItemType Directory -Force -Path (Join-Path $VerifyPackageDir "windows") | Out-Null
    Copy-Item (Join-Path $RootDir "target\windows\ren_sdk.dll") (Join-Path $VerifyPackageDir "windows\ren_sdk.dll") -Force
  }
  Copy-Item (Join-Path $RootDir "target\ren_sdk.h") (Join-Path $VerifyPackageDir "ren_sdk.h") -Force

  $hashLines = New-Object System.Collections.Generic.List[string]
  Get-ChildItem -Path $VerifyPackageDir -File -Recurse |
    Where-Object { $_.Name -ne "SHA256SUMS.txt" } |
    Sort-Object FullName |
    ForEach-Object {
      $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
      $relative = $_.FullName.Substring($VerifyPackageDir.Length + 1).Replace('\','/')
      $hashLines.Add("$hash  $relative")
    }
  $hashLines | Set-Content -Path (Join-Path $VerifyPackageDir "SHA256SUMS.txt") -Encoding ascii
  Write-AllowlistFile
}

function Sync-ToBackendAndServer {
  Log "syncing verification package to local backend path: $SdkVerifyLocalDir"
  New-Item -ItemType Directory -Force -Path $SdkVerifyLocalDir | Out-Null
  Get-ChildItem $SdkVerifyLocalDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
  Copy-Item (Join-Path $VerifyPackageDir "*") $SdkVerifyLocalDir -Recurse -Force

  if (-not [string]::IsNullOrWhiteSpace($SdkVerifyScpTarget)) {
    if ($SkipRemoteUpload -eq "1") {
      Log "SDK_SKIP_REMOTE_UPLOAD=1, skipping remote upload"
      return
    }
    Require-Command "scp"
    Log "uploading verification package via scp to $SdkVerifyScpTarget"
    & scp -r $VerifyPackageDir $SdkVerifyScpTarget
  } else {
    Log "SDK_VERIFY_SCP_TARGET is empty, skipping remote upload"
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
Prepare-VerificationPackage
Sync-ToBackendAndServer

Log "done"
