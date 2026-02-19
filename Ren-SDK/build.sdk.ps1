param(
  [switch]$AndroidOnly,
  [switch]$NoUpload,
  [switch]$NoSyncFlutter
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $IsWindows) {
  throw "build.sdk.ps1 is for Windows. Use build.sdk.sh on macOS."
}

$env:SDK_BUILD_ANDROID_ONLY = if ($AndroidOnly) { "1" } else { "0" }
$env:SDK_SKIP_REMOTE_UPLOAD = if ($NoUpload) { "1" } else { "0" }
$env:SDK_SKIP_FLUTTER_SYNC = if ($NoSyncFlutter) { "1" } else { "0" }

& (Join-Path $RootDir "build.windows.ps1")
