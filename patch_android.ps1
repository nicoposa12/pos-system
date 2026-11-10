# TindaKo Android Shorebird OTA Patch Script
# Automatically deploys Over-The-Air code patches to Android devices.

param(
    [string]$ReleaseVersion = "1.0.2+3",
    [string]$Track = "stable"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = Get-Location }
$mobileDir = Join-Path $scriptDir "mobile"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "🚀 Deploying TindaKo Android OTA Patch..." -ForegroundColor Cyan
Write-Host "📱 Target Release: $ReleaseVersion" -ForegroundColor Yellow
Write-Host "📡 Track: $Track" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

Set-Location $mobileDir
try {
    shorebird patch android --release-version $ReleaseVersion --track $Track
    if ($LASTEXITCODE -ne 0) {
        throw "Shorebird patch command failed."
    }
} finally {
    Set-Location $scriptDir
}

Write-Host ""
Write-Host "✅ SUCCESS! Android patch published to track '$Track' for release $ReleaseVersion." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

