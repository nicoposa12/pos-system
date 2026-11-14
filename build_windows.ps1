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

# Keep Dart UpdateService fallback constants and Inno Setup script in sync with build version
$updateServicePath = Join-Path $mobileDir "lib\services\update_service.dart"
if (Test-Path $updateServicePath) {
    $usContent = Get-Content $updateServicePath -Raw
    $usUpdated = $usContent `
        -replace "(?ms)(static const String currentVersion = String\.fromEnvironment\(\s*'APP_VERSION',\s*defaultValue:\s*')[^']+('\s*,?\s*\);)", "`${1}$semVer`${2}" `
        -replace "(?ms)(static const int currentBuildNumber = int\.fromEnvironment\(\s*'APP_BUILD_NUMBER',\s*defaultValue:\s*)\d+(\s*,?\s*\);)", "`${1}$buildNum`${2}"
    if ($usUpdated -ne $usContent) {
        Set-Content -Path $updateServicePath -Value $usUpdated -NoNewline
        Write-Host "Synced UpdateService defaults to v$semVer+$buildNum." -ForegroundColor Cyan
    }
}

if (Test-Path $issPath) {
    $issContent = Get-Content $issPath -Raw
    $issUpdated = $issContent -replace '(?m)^#define MyAppVersion ".*"$', "#define MyAppVersion `"$semVer`""
    if ($issUpdated -ne $issContent) {
        Set-Content -Path $issPath -Value $issUpdated -NoNewline
        Write-Host "Synced installer.iss MyAppVersion to $semVer." -ForegroundColor Cyan
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "🚀 Building TindaKo Windows v$semVer (Build $buildNum)..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 2. Flutter Build Windows
Set-Location $mobileDir
Write-Host "[1/3] Compiling Flutter Windows release binary..." -ForegroundColor Yellow
flutter build windows --release --build-name=$semVer --build-number=$buildNum --dart-define=APP_VERSION=$semVer --dart-define=APP_BUILD_NUMBER=$buildNum
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
$expectedSetupPath = Join-Path $installerDir "TindaKo-Setup-v$semVer.exe"
$latestSetup = if (Test-Path $expectedSetupPath) {
    Get-Item $expectedSetupPath
} else {
    Get-ChildItem -Path $installerDir -Filter "TindaKo-Setup-v*.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

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

# 6. Check backend release manifest sync & remind remote deployment steps
$backendUpdatesPath = Join-Path $scriptDir "backend\config\updates.php"
$backendVerMatch = $false
if (Test-Path $backendUpdatesPath) {
    $updatesContent = Get-Content $backendUpdatesPath -Raw
    if ($updatesContent -match "env\('WINDOWS_APP_VERSION',\s*'([^']+)'\)" -and $matches[1] -eq $semVer -and
        $updatesContent -match "env\('WINDOWS_BUILD_NUMBER',\s*(\d+)\)" -and $matches[1] -eq $buildNum) {
        $backendVerMatch = $true
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "REMOTE CLIENT RELEASE CHECKLIST (v$semVer+$buildNum)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
if (-not $backendVerMatch) {
    Write-Host "WARNING: backend/config/updates.php does not match v$semVer (Build $buildNum)!" -ForegroundColor Red
}
Write-Host "1. Create/publish GitHub Release tag 'v$semVer' FIRST and upload:" -ForegroundColor White
Write-Host "   $($latestSetup.FullName)" -ForegroundColor Yellow
Write-Host "2. Deploy backend (backend/config/updates.php -> v$semVer, build $buildNum) to Render," -ForegroundColor White
Write-Host "   and verify Render Environment Variables (WINDOWS_APP_VERSION / WINDOWS_BUILD_NUMBER)" -ForegroundColor White
Write-Host "   are not pinned to an older version." -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
