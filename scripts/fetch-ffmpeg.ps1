# Downloads FFmpeg (gyan.dev essentials build) and places ffmpeg.exe / ffprobe.exe
# into src-tauri/binaries with the triplet-suffix Tauri's sidecar system expects.
#
# Usage:  pwsh -File scripts/fetch-ffmpeg.ps1

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$binDir = Join-Path $root "src-tauri\binaries"
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

$url = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
$zipPath = Join-Path $env:TEMP "ffmpeg-essentials.zip"
$extractDir = Join-Path $env:TEMP "ffmpeg-essentials-extract"

Write-Host "Downloading FFmpeg essentials from gyan.dev..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir }
Write-Host "Extracting..." -ForegroundColor Cyan
Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

$ffmpegSrc  = Get-ChildItem -Path $extractDir -Recurse -Filter ffmpeg.exe  | Select-Object -First 1
$ffprobeSrc = Get-ChildItem -Path $extractDir -Recurse -Filter ffprobe.exe | Select-Object -First 1
if (-not $ffmpegSrc -or -not $ffprobeSrc) {
    throw "Could not locate ffmpeg.exe / ffprobe.exe in the extracted archive."
}

# Determine Rust host triple (e.g. x86_64-pc-windows-msvc) so Tauri can find the sidecar.
try {
    $hostTriple = (rustc -vV) -split "`n" | Where-Object { $_ -match "^host: " } | ForEach-Object { ($_ -split ": ")[1].Trim() }
} catch {
    $hostTriple = "x86_64-pc-windows-msvc"
}
if (-not $hostTriple) { $hostTriple = "x86_64-pc-windows-msvc" }

$ffmpegDst  = Join-Path $binDir ("ffmpeg-"  + $hostTriple + ".exe")
$ffprobeDst = Join-Path $binDir ("ffprobe-" + $hostTriple + ".exe")

Copy-Item $ffmpegSrc.FullName  $ffmpegDst  -Force
Copy-Item $ffprobeSrc.FullName $ffprobeDst -Force

Write-Host "Installed:" -ForegroundColor Green
Write-Host "  $ffmpegDst"
Write-Host "  $ffprobeDst"
Write-Host "Done." -ForegroundColor Green
