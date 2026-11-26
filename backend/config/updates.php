<?php

$windowsVersion = (string) env('WINDOWS_APP_VERSION', '1.0.8');
$windowsBuildNumber = (int) env('WINDOWS_BUILD_NUMBER', 9);
$defaultDownloadUrl = "https://github.com/nicoposa12/pos-system/releases/download/v{$windowsVersion}/TindaKo-Setup-v{$windowsVersion}.exe";
$configuredDownloadUrl = env('WINDOWS_DOWNLOAD_URL');

return [
    'windows' => [
        'version' => $windowsVersion,
        'build_number' => $windowsBuildNumber,
        'download_url' => is_string($configuredDownloadUrl) && trim($configuredDownloadUrl) !== ''
            ? trim($configuredDownloadUrl)
            : $defaultDownloadUrl,
        'release_notes' => env(
            'WINDOWS_RELEASE_NOTES',
            'TindaKo v1.0.8 (Build 9) adding cost price & profit tracking, live stock badges on Best Sellers, and PDF exports for Best Sellers & Inventory.'
        ),
        'force_update' => (bool) env('WINDOWS_FORCE_UPDATE', false),
    ],
    'android' => [
        'version' => (string) env('ANDROID_APP_VERSION', '1.0.8'),
        'build_number' => (int) env('ANDROID_BUILD_NUMBER', 9),
    ],
];
