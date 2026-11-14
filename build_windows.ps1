# TindaKo Windows Build, Package & Realtime Live-Update Script
# Automatically builds the Flutter Windows release, compiles the Inno Setup installer,
# updates the local installation, and relaunches the app in real-time.

param(
    [string]$Version = "",
    [switch]$NoInstall,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = Get-Location }
$mobileDir = Join-Path $scriptDir "mobile"
$isccPath = "C:\Users\basco\AppData\Local\Programs\Inno Setup 6\ISCC.exe"
$pubspecPath = Join-Path $mobileDir "pubspec.yaml"
$issPath = Join-Path $mobileDir "windows\installer.iss"

# 1. Detect or update version
$currentVersionLine = Get-Content $pubspecPath | Where-Object { $_ -match '^version:\s*(.+)$' } | Select-Object -First 1
$currentFullVersion = if ($currentVersionLine -match '^version:\s*(.+)$') { $matches[1].Trim() } else { "1.0.4+5" }
$targetVersion = if ($Version) { $Version } else { $currentFullVersion }

if ($targetVersion -match '^([0-9]+\.[0-9]+\.[0-9]+)(\+([0-9]+))?$') {
    $semVer = $matches[1]
    $buildNum = if ($matches[3]) { $matches[3] } else { "1" }
} else {
    $semVer = $targetVersion
    $buildNum = "1"
}

if ($Version -and ($targetVersion -ne $currentFullVersion)) {
    Write-Host "Updating pubspec.yaml version to $targetVersion..." -ForegroundColor Cyan
    $pubContent = Get-Content $pubspecPath -Raw
    $pubContent = $pubContent -replace '(?m)^version:\s*.+$', "version: $targetVersion"
    Set-Content -Path $pubspecPath -Value $pubContent -NoNewline
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "🚀 Building TindaKo Windows v$semVer (Build $buildNum)..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 2. Flutter Build Windows
Set-Location $mobileDir
Write-Host "[1/3] Compiling Flutter Windows release binary..." -ForegroundColor Yellow
flutter build windows --release --build-name=$semVer --build-number=$buildNum
if ($LASTEXITCODE -ne 0) {
    Set-Location $scriptDir
    throw "Flutter build failed."
}
Set-Location $scriptDir

# 3. Compile Inno Setup Installer
if (-not (Test-Path $isccPath)) {
    throw "Inno Setup compiler not found at: $isccPath"
}

Write-Host "[2/3] Compiling Inno Setup 1-click Installer..." -ForegroundColor Yellow
& $isccPath "/DMyAppVersion=$semVer" $issPath

if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed."
}

# 4. Create fresh alias copy
$installerDir = Join-Path $mobileDir "build\windows\installer"
$latestSetup = Get-ChildItem -Path $installerDir -Filter "TindaKo-Setup-v*.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($latestSetup) {
    Copy-Item $latestSetup.FullName (Join-Path $installerDir "TindaKo-Setup.exe") -Force
}

Write-Host ""
Write-Host "✅ Installer generated successfully!" -ForegroundColor Green
Write-Host "📦 File: $($latestSetup.FullName)" -ForegroundColor White
Write-Host "📊 Size: $([math]::Round($latestSetup.Length / 1MB, 2)) MB" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

# 5. Real-time Live Update & Local Launch
if (-not $NoInstall -and $latestSetup) {
    Write-Host "[3/3] 🔄 Applying update to local PC in real-time..." -ForegroundColor Yellow
    
    # Silently install and close existing running instance
    Start-Process -FilePath $latestSetup.FullName -ArgumentList "/SILENT", "/FORCECLOSEAPPLICATIONS" -Wait
    Write-Host "✅ Local installation updated successfully!" -ForegroundColor Green
    
    if (-not $NoLaunch) {
        $appExe = Join-Path $env:LOCALAPPDATA "Programs\TindaKo\tindako.exe"
        if (Test-Path $appExe) {
            Write-Host "🚀 Launching updated TindaKo POS..." -ForegroundColor Cyan
            Start-Process -FilePath $appExe
        }
    }
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "🎉 Updates are now live on your PC in real-time!" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Tip: To install this build on your PC manually, run:" -ForegroundColor Gray
    Write-Host "  Start-Process '$($latestSetup.FullName)'" -ForegroundColor Gray
}
