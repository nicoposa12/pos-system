<?php

namespace App\Traits;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

trait HandlesStorePhotoUpload
{
    /**
     * Get configured upload disk (R2, S3, or public fallback).
     */
    protected function getUploadDisk(): string
    {
        if (app()->environment('testing')) {
            return 'public';
        }

        $defaultDisk = config('filesystems.default', 'r2');
        if (config("filesystems.disks.{$defaultDisk}.key")) {
            return $defaultDisk;
        }

        if (config('filesystems.disks.r2.key')) {
            return 'r2';
        }

        if (config('filesystems.disks.s3.key')) {
            return 's3';
        }

        return 'public';
    }

    /**
     * Disks to check for existing images, skipping unconfigured cloud credentials.
     */
    protected function getDisksToCheck(): array
    {
        if (app()->environment('testing')) {
            return ['public'];
        }

        $disks = [$this->getUploadDisk()];
        if (!empty(config('filesystems.disks.r2.key'))) {
            $disks[] = 'r2';
        }
        if (!empty(config('filesystems.disks.s3.key'))) {
            $disks[] = 's3';
        }
        $disks[] = 'public';

        return array_values(array_unique($disks));
    }

    /**
     * Safely upload store photo to Cloudflare R2 / S3 / Local storage.
     */
    protected function handleStorePhotoUpload(Request $request, ?string $oldImagePath = null): ?string
    {
        if (!$request->hasFile('image')) {
            return null;
        }

        $disk = $this->getUploadDisk();
        $file = $request->file('image');

        try {
            if ($oldImagePath) {
                $this->deleteStorePhotoIfExists($oldImagePath, $disk);
            }

            $guessedExt = strtolower($file->extension() ?: ($file->guessExtension() ?: 'jpg'));
            $allowedExtensions = ['jpg', 'jpeg', 'png', 'webp'];
            $extension = in_array($guessedExt, $allowedExtensions, true) ? $guessedExt : 'jpg';
            $filename = Str::random(32) . '.' . $extension;

            $path = $file->storeAs('stores', $filename, [
                'disk' => $disk,
            ]);

            return url('/api/media/' . ltrim($path, '/'));
        } catch (\Throwable $e) {
            Log::error("Store photo upload to disk [{$disk}] failed: " . $e->getMessage());

            if ($disk !== 'public') {
                try {
                    $fallbackFilename = Str::random(32) . '.' . $extension;
                    $fallbackPath = $file->storeAs('stores', $fallbackFilename, 'public');
                    return url('/api/media/' . ltrim($fallbackPath, '/'));
                } catch (\Throwable $fallbackErr) {
                    Log::error('Local fallback store upload also failed: ' . $fallbackErr->getMessage());
                }
            }

            return null;
        }
    }

    /**
     * Delete stored store photo from cloud or local disk if it exists.
     */
    protected function deleteStorePhotoIfExists(?string $imagePath, ?string $disk = null): void
    {
        if (!$imagePath) return;
        $disk = $disk ?? $this->getUploadDisk();
        try {
            $parsedPath = parse_url($imagePath, PHP_URL_PATH);
            $cleanPath = ltrim($parsedPath ?? $imagePath, '/');
            $cleanPath = preg_replace('#^(storage/|api/media/)#', '', $cleanPath);

            $disksToCheck = $this->getDisksToCheck();
            foreach ($disksToCheck as $d) {
                try {
                    if (Storage::disk($d)->exists($cleanPath)) {
                        Storage::disk($d)->delete($cleanPath);
                        break;
                    }
                } catch (\Throwable) {}
            }
        } catch (\Throwable $e) {
            Log::warning("deleteStorePhotoIfExists error: " . $e->getMessage());
        }
    }
}

