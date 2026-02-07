param(
  [Parameter(Mandatory=$true)]
  [ValidateSet('windows','linux','macos','ios','android')]
  [string]$Platform,

  [switch]$Debug,
  [switch]$Release,

  [string]$Device,

  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$ExtraArgs
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ScriptsDir = $PSScriptRoot
$FlutterDir = Join-Path $RepoRoot 'apps\flutter'
$RenSdkDir = Join-Path $RepoRoot 'Ren-SDK'

function Require-Command([string]$Name) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) { throw "Missing dependency: '$Name' (not found in PATH)" }
}

function Ensure-Flutter {
  Require-Command 'flutter'
  if (-not (Test-Path $FlutterDir)) { throw "Missing Flutter app dir: $FlutterDir" }
}

function Ensure-RenSdk {
  if (-not (Test-Path $RenSdkDir)) { throw "Missing Ren-SDK dir: $RenSdkDir" }
  $buildSh = Join-Path $RenSdkDir 'build.sh'
  if (-not (Test-Path $buildSh)) { throw "Missing Ren-SDK build.sh: $buildSh" }
}

function Flutter-PubGet-IfNeeded {
  Ensure-Flutter
  $dartTool = Join-Path $FlutterDir '.dart_tool'
  if (-not (Test-Path $dartTool)) {
    & flutter pub get | Write-Output
  }
}

function Sync-Ios-Xcframework {
  $src = Join-Path $RenSdkDir 'target\RenSDK.xcframework'
  $dest = Join-Path $FlutterDir 'ios\RenSDK.xcframework'
  if (-not (Test-Path $src)) { throw "Ren-SDK iOS artifact not found: $src" }
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  Copy-Item -Recurse -Force $src $dest
}

function Sync-Android-JniLibs {
  $src = Join-Path $RenSdkDir 'target\android\jniLibs'
  $dest = Join-Path $FlutterDir 'android\app\src\main\jniLibs'
  if (-not (Test-Path $src)) { throw "Ren-SDK Android artifact not found: $src" }
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Recurse -Force (Join-Path $src '*') $dest
}

function Sync-Windows-Dll {
  $src1 = Join-Path $RenSdkDir 'pkg\windows\ren_sdk.dll'
  $src2 = Join-Path $RenSdkDir 'target\release\ren_sdk.dll'
  $dest = Join-Path $FlutterDir 'ren_sdk.dll'

  if (Test-Path $src1) {
    Copy-Item -Force $src1 $dest
  } elseif (Test-Path $src2) {
    Copy-Item -Force $src2 $dest
  } else {
    throw "Ren-SDK Windows DLL not found: $src1 or $src2"
  }
}

function Sync-Linux-So {
  $src1 = Join-Path $RenSdkDir 'target\linux\libren_sdk.so'
  $src2 = Join-Path $RenSdkDir 'target\release\libren_sdk.so'
  $dest = Join-Path $FlutterDir 'libren_sdk.so'

  if (Test-Path $src1) {
    Copy-Item -Force $src1 $dest
  } elseif (Test-Path $src2) {
    Copy-Item -Force $src2 $dest
  } else {
    throw "Ren-SDK Linux SO not found: $src1 or $src2"
  }
}

function Build-RenSdk([string]$Platform) {
  Ensure-RenSdk

  $bash = Get-Command bash -ErrorAction SilentlyContinue
  if (-not $bash) {
    throw "'bash' is required on Windows to run Ren-SDK/build.sh. Install Git for Windows (Git Bash) or MSYS2." 
  }

  Push-Location $RenSdkDir
  try {
    & bash ./build.sh $Platform
  } finally {
    Pop-Location
  }
}

function Sync-RenSdk([string]$Platform) {
  switch ($Platform) {
    'ios' { Sync-Ios-Xcframework }
    'android' { Sync-Android-JniLibs }
    'windows' { Sync-Windows-Dll }
    'linux' { Sync-Linux-So }
    default { }
  }
}

# Determine mode
$Mode = 'debug'
if ($Release -and $Debug) { throw 'Choose either -Release or -Debug' }
if ($Release) { $Mode = 'release' }
if ($Debug) { $Mode = 'debug' }

Ensure-Flutter
Push-Location $FlutterDir
try {
  Flutter-PubGet-IfNeeded

  Build-RenSdk $Platform
  Sync-RenSdk $Platform

  $runArgs = @('run', "--$Mode")
  if ($Device) {
    $runArgs += @('-d', $Device)
  } else {
    if ($Platform -in @('windows','linux','macos')) {
      $runArgs += @('-d', $Platform)
    } elseif ($Platform -eq 'android') {
      $runArgs += @('-d', 'android')
    }
  }

  if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
    $runArgs += $ExtraArgs
  }

  & flutter @runArgs
} finally {
  Pop-Location
}
