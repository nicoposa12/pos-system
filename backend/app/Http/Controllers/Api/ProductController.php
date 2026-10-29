<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Product;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

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

        $imagePath = null;
        if ($request->hasFile('image')) {
            $disk = env('FILESYSTEM_DISK', 'public');
            $path = $request->file('image')->store('products', $disk);
            $imagePath = Storage::disk($disk)->url($path);
        }

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
            $disk = env('FILESYSTEM_DISK', 'public');
            $this->deleteImageIfExists($product->image_path);
            $path = $request->file('image')->store('products', $disk);
            $validated['image_path'] = Storage::disk($disk)->url($path);
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
     * Delete stored image file from local or cloud storage if it exists.
     */
    private function deleteImageIfExists(?string $imagePath): void
    {
        if (!$imagePath) {
            return;
        }

        $disk = env('FILESYSTEM_DISK', 'public');
        try {
            $parsedPath = parse_url($imagePath, PHP_URL_PATH);
            $cleanPath = ltrim($parsedPath ?? $imagePath, '/');
            $cleanPath = preg_replace('#^storage/#', '', $cleanPath);

            if (Storage::disk($disk)->exists($cleanPath)) {
                Storage::disk($disk)->delete($cleanPath);
            }
        } catch (\Throwable $e) {
            // Silently ignore if remote file is already missing
        }
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
