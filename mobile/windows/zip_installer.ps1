$installer = 'mobile\build\windows\installer\TindaKo-Setup-v1.0.2.exe'
$zip = 'mobile\build\windows\installer\TindaKo-Setup-v1.0.2.zip'
if (Test-Path $installer) {
    Compress-Archive -Path $installer -DestinationPath $zip -Force
    Write-Output "Zip created successfully: $zip"
    Get-Item $zip | Select-Object Name, Length, LastWriteTime
}

