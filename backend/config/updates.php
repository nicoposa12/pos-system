<?php

$windowsVersion = (string) env('WINDOWS_APP_VERSION', '1.0.7');
$windowsBuildNumber = (int) env('WINDOWS_BUILD_NUMBER', 8);
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
            'TindaKo v1.0.7 (Build 8) adding store-scoped sequential order numbers.'
        ),
        'force_update' => (bool) env('WINDOWS_FORCE_UPDATE', false),
    ],
    'android' => [
        'version' => (string) env('ANDROID_APP_VERSION', '1.0.7'),
        'build_number' => (int) env('ANDROID_BUILD_NUMBER', 8),
    ],
];
