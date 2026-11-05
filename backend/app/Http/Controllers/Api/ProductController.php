<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Product;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class ProductController extends Controller
{
    /**
     * Display a listing of products for the authenticated store user.
     */
    public function index(Request $request)
    {
        $query = $request->user()->products();

        if ($request->filled('search')) {
            $search = $request->input('search');
            $query->where(function ($q) use ($search) {
                $q->where('name', 'like', "%{$search}%")
                  ->orWhere('barcode', 'like', "%{$search}%");
            });
        }

        if ($request->filled('category')) {
            $query->where('category', $request->input('category'));
        }

        $products = $query->latest()->get();

        return response()->json([
            'products' => $products,
        ]);
    }

    /**
     * Store a new product in storage.
     */
    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'category' => 'nullable|string|max:100',
            'price' => 'required|numeric|min:0',
            'stock' => 'required|integer|min:0',
            'barcode' => 'nullable|string|max:100',
            'variants' => 'nullable',
            'image' => 'nullable|image|max:4096', // 4MB max
        ]);

        // Idempotency: Prevent accidental duplicate submissions from spam clicks within 3 seconds
        $existingRecent = $request->user()->products()
            ->where('name', $validated['name'])
            ->where('price', $validated['price'])
            ->where('created_at', '>=', now()->subSeconds(3))
            ->first();

        if ($existingRecent) {
            return response()->json([
                'message' => 'Product was already created',
                'product' => $existingRecent,
            ], 200);
        }

        $imagePath = $this->handleImageUpload($request);

        $product = $request->user()->products()->create([
            'name' => $validated['name'],
            'category' => $validated['category'] ?? null,
            'price' => $validated['price'],
            'stock' => $validated['stock'],
            'barcode' => $validated['barcode'] ?? null,
            'image_path' => $imagePath,
            'variants' => is_string($validated['variants'] ?? null)
                ? json_decode($validated['variants'], true)
                : ($validated['variants'] ?? null),
        ]);

        return response()->json([
            'message' => 'Product created successfully',
            'product' => $product,
        ], 201);
    }

    /**
     * Display the specified product.
     */
    public function show(Request $request, Product $product)
    {
        if ($product->user_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        return response()->json(['product' => $product]);
    }

    /**
     * Update the specified product.
     */
    public function update(Request $request, Product $product)
    {
        if ($product->user_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $validated = $request->validate([
            'name' => 'sometimes|required|string|max:255',
            'category' => 'nullable|string|max:100',
            'price' => 'sometimes|required|numeric|min:0',
            'stock' => 'sometimes|required|integer|min:0',
            'barcode' => 'nullable|string|max:100',
            'variants' => 'nullable',
            'image' => 'nullable|image|max:4096',
        ]);

        if ($request->hasFile('image')) {
            $newImagePath = $this->handleImageUpload($request, $product->image_path);
            if ($newImagePath) {
                $validated['image_path'] = $newImagePath;
            }
        }

        if (isset($validated['variants']) && is_string($validated['variants'])) {
            $validated['variants'] = json_decode($validated['variants'], true);
        }

        $product->update($validated);

        return response()->json([
            'message' => 'Product updated successfully',
            'product' => $product,
        ]);
    }

    /**
     * Remove the specified product.
     */
    public function destroy(Request $request, Product $product)
    {
        if ($product->user_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $this->deleteImageIfExists($product->image_path);

        $product->delete();

        return response()->json([
            'message' => 'Product deleted successfully',
        ]);
    }

    /**
     * Determine the active upload disk.
     * Prefers 'r2' if credentials exist, then 's3', then falls back to 'public'.
     */
    private function getUploadDisk(): string
    {
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
     * Safely upload product image to Cloudflare R2 / S3 / Local storage.
     */
    private function handleImageUpload(Request $request, ?string $oldImagePath = null): ?string
    {
        if (!$request->hasFile('image')) {
            return null;
        }

        $disk = $this->getUploadDisk();
        $file = $request->file('image');

        try {
            if ($oldImagePath) {
                $this->deleteImageIfExists($oldImagePath, $disk);
            }

            // Generate clean random filename
            $extension = $file->getClientOriginalExtension() ?: 'jpg';
            $filename = Str::random(32) . '.' . strtolower($extension);

            $path = $file->storeAs('products', $filename, [
                'disk' => $disk,
            ]);

            // Return media proxy URL so images are accessible across all mobile and ISP networks
            return url('/api/media/' . ltrim($path, '/'));
        } catch (\Throwable $e) {
            Log::error("Product image upload to disk [{$disk}] failed: " . $e->getMessage(), [
                'exception' => $e,
            ]);

            // Fallback to local public disk so customer never loses photo
            if ($disk !== 'public') {
                try {
                    $fallbackFilename = Str::random(32) . '.' . strtolower($file->getClientOriginalExtension() ?: 'jpg');
                    $fallbackPath = $file->storeAs('products', $fallbackFilename, 'public');
                    Log::info("Fallback product image upload to [public] succeeded: {$fallbackPath}");
                    return url('/api/media/' . ltrim($fallbackPath, '/'));
                } catch (\Throwable $fallbackErr) {
                    Log::error('Local fallback upload also failed: ' . $fallbackErr->getMessage());
                }
            }

            return null;
        }
    }

    /**
     * Delete stored image file from local or cloud storage if it exists.
     */
    private function deleteImageIfExists(?string $imagePath, ?string $disk = null): void
    {
        if (!$imagePath) {
            return;
        }

        $disk = $disk ?? $this->getUploadDisk();
        try {
            $parsedPath = parse_url($imagePath, PHP_URL_PATH);
            $cleanPath = ltrim($parsedPath ?? $imagePath, '/');
            $cleanPath = preg_replace('#^(storage/|api/media/)#', '', $cleanPath);

            $disksToCheck = array_unique([$disk, 'r2', 's3', 'public']);
            foreach ($disksToCheck as $d) {
                try {
                    if (Storage::disk($d)->exists($cleanPath)) {
                        Storage::disk($d)->delete($cleanPath);
                    }
                } catch (\Throwable $e) {
                    // Ignore
                }
            }
        } catch (\Throwable $e) {
            // Silently ignore if remote file is already missing
        }
    }

    /**
     * Public proxy endpoint to serve product images directly through the API.
     * Streams images from Cloudflare R2 / S3 / Local storage.
     * Completely bypasses ISP DNS/SNI blocks on *.r2.dev subdomains.
     */
    public function serveImage(string $filename)
    {
        $filename = basename($filename);
        if (!preg_match('/^[a-zA-Z0-9_\-\.]+$/', $filename)) {
            abort(404, 'Invalid image name');
        }

        $path = 'products/' . $filename;
        $headers = [
            'Cache-Control' => 'public, max-age=31536000, immutable',
        ];

        // Check active disk first, then other cloud/local disks
        $disksToCheck = array_unique([$this->getUploadDisk(), 'r2', 's3', 'public']);

        foreach ($disksToCheck as $diskName) {
            try {
                if (Storage::disk($diskName)->exists($path)) {
                    return Storage::disk($diskName)->response($path, $filename, $headers);
                }
            } catch (\Throwable $e) {
                Log::warning("serveImage could not load [{$path}] from disk [{$diskName}]: " . $e->getMessage());
            }
        }

        abort(404, 'Image not found');
    }

    /**
     * Find product instantly by barcode.
     */
    public function byBarcode(Request $request, string $barcode)
    {
        $product = $request->user()->products()->where('barcode', $barcode)->first();

        if (!$product) {
            return response()->json(['message' => 'Product not found'], 404);
        }

        return response()->json(['product' => $product]);
    }
}
