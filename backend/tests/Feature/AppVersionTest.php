<?php

namespace Tests\Feature;

use Tests\TestCase;

class AppVersionTest extends TestCase
{
    public function test_app_version_endpoint_returns_expected_manifest_structure(): void
    {
        $response = $this->getJson('/api/app/version');

        $response->assertOk()
            ->assertJsonStructure([
                'windows' => [
                    'version',
                    'build_number',
                    'download_url',
                    'release_notes',
                    'force_update',
                ],
                'android' => [
                    'version',
                    'build_number',
                ],
            ]);

        $version = $response->json('windows.version');
        $this->assertSame(config('updates.windows.version'), $version);
        $this->assertStringContainsString(
            "TindaKo-Setup-v{$version}.exe",
            (string) $response->json('windows.download_url')
        );
    }

    public function test_app_version_endpoint_reads_from_updates_config(): void
    {
        config()->set('updates.windows', [
            'version' => '1.9.0',
            'build_number' => 42,
            'download_url' => 'https://github.com/nicoposa12/pos-system/releases/download/v1.9.0/TindaKo-Setup-v1.9.0.exe',
            'release_notes' => 'Test release',
            'force_update' => true,
        ]);

        $response = $this->getJson('/api/app/version');

        $response->assertOk()
            ->assertJsonPath('windows.version', '1.9.0')
            ->assertJsonPath('windows.build_number', 42)
            ->assertJsonPath('windows.force_update', true);
    }
}
