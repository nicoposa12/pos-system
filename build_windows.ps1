# TindaKo Windows Build & Package Script
# Automatically builds the Flutter Windows release and compiles the single-click Inno Setup installer.

param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = Get-Location }
$mobileDir = Join-Path $scriptDir "mobile"
$isccPath = "C:\Users\basco\AppData\Local\Programs\Inno Setup 6\ISCC.exe"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Building TindaKo Windows Release..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Flutter Build Windows
Set-Location $mobileDir
Write-Host "Compiling Flutter Windows release binary..." -ForegroundColor Yellow
flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    Set-Location $scriptDir
    throw "Flutter build failed."
}
Set-Location $scriptDir

# 2. Compile Inno Setup Installer
if (-not (Test-Path $isccPath)) {
    throw "Inno Setup compiler not found at: $isccPath"
}

Write-Host "Compiling Inno Setup 1-click Installer..." -ForegroundColor Yellow
$issPath = Join-Path $mobileDir "windows\installer.iss"
& $isccPath $issPath

if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed."
}

# 3. Create fresh alias copy
$installerDir = Join-Path $mobileDir "build\windows\installer"
$latestSetup = Get-ChildItem -Path $installerDir -Filter "TindaKo-Setup-v*.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($latestSetup) {
    Copy-Item $latestSetup.FullName (Join-Path $installerDir "TindaKo-Setup.exe") -Force
}

Write-Host ""
Write-Host "SUCCESS! Windows Installer is ready:" -ForegroundColor Green
Write-Host "File: $($latestSetup.FullName)" -ForegroundColor White
Write-Host "Size: $([math]::Round($latestSetup.Length / 1MB, 2)) MB" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
