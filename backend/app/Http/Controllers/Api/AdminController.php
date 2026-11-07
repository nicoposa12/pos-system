<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Debt;
use App\Models\Product;
use App\Models\Transaction;
use App\Models\User;
use App\Services\AuditLogger;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

class AdminController extends Controller
{
    /**
     * List all users/clients with summary statistics.
     */
    public function index(Request $request)
    {
        $search = $request->query('search');
        $role = $request->query('role');
        $status = $request->query('status');

        $query = User::query()
            ->withCount(['products', 'transactions', 'debts'])
            ->withSum('transactions', 'total_amount');

        if (!empty($search)) {
            $query->where(function ($q) use ($search) {
                $q->where('username', 'like', "%{$search}%")
                  ->orWhere('full_name', 'like', "%{$search}%")
                  ->orWhere('email', 'like', "%{$search}%");
            });
        }

        if (!empty($role)) {
            $query->where('role', $role);
        }

        if ($status !== null && $status !== '') {
            $query->where('is_active', filter_var($status, FILTER_VALIDATE_BOOLEAN));
        }

        $users = $query->orderBy('created_at', 'desc')->get();

        $formattedUsers = $users->map(function ($u) {
            return [
                'id' => $u->id,
                'username' => $u->username,
                'full_name' => $u->full_name,
                'email' => $u->email,
                'image_path' => $u->image_path,
                'role' => $u->role ?? 'client',
                'is_active' => (bool) $u->is_active,
                'has_pin' => !empty($u->pin),
                'created_at' => $u->created_at ? $u->created_at->toIso8601String() : null,
                'stats' => [
                    'products_count' => (int) $u->products_count,
                    'transactions_count' => (int) $u->transactions_count,
                    'debts_count' => (int) $u->debts_count,
                    'total_sales' => (float) ($u->transactions_sum_total_amount ?? 0),
                ],
            ];
        });

        // Network-wide summary metrics
        $totalUsers = User::count();
        $totalClients = User::where('role', '!=', 'admin')->count();
        $activeClients = User::where('role', '!=', 'admin')->where('is_active', true)->count();
        $inactiveClients = User::where('role', '!=', 'admin')->where('is_active', false)->count();
        $totalNetworkSales = (float) Transaction::sum('total_amount');
        $totalNetworkProducts = (int) Product::count();

        return response()->json([
            'summary' => [
                'total_users' => $totalUsers,
                'total_clients' => $totalClients,
                'active_clients' => $activeClients,
                'inactive_clients' => $inactiveClients,
                'total_network_sales' => $totalNetworkSales,
                'total_network_products' => $totalNetworkProducts,
            ],
            'clients' => $formattedUsers,
        ]);
    }

    /**
     * Create a new client or admin account.
     */
    public function store(Request $request)
    {
        $validated = $request->validate([
            'username' => 'required|string|max:50|unique:users,username',
            'full_name' => 'required|string|max:100',
            'email' => 'nullable|email|max:150|unique:users,email',
            'password' => 'required|string|min:4',
            'pin' => 'nullable|string|digits_between:4,6',
            'role' => 'nullable|string|in:admin,client',
            'is_active' => 'nullable|boolean',
            'image' => 'nullable|image|mimes:jpeg,png,jpg,webp|max:4096',
            'image_path' => 'nullable|string',
        ]);

        if ($request->hasFile('image')) {
            $imagePath = $this->handleStorePhotoUpload($request);
            if ($imagePath) {
                $validated['image_path'] = $imagePath;
            }
        }

        $user = User::create([
            'username' => $validated['username'],
            'full_name' => $validated['full_name'],
            'email' => $validated['email'] ?? null,
            'password' => Hash::make($validated['password']),
            'pin' => !empty($validated['pin']) ? Hash::make($validated['pin']) : null,
            'role' => $validated['role'] ?? 'client',
            'is_active' => $validated['is_active'] ?? true,
            'image_path' => $validated['image_path'] ?? null,
        ]);

        return response()->json([
            'message' => 'Account created successfully',
            'user' => [
                'id' => $user->id,
                'username' => $user->username,
                'full_name' => $user->full_name,
                'email' => $user->email,
                'image_path' => $user->image_path,
                'role' => $user->role,
                'is_active' => (bool) $user->is_active,
                'has_pin' => !empty($user->pin),
                'created_at' => $user->created_at->toIso8601String(),
                'stats' => [
                    'products_count' => 0,
                    'transactions_count' => 0,
                    'debts_count' => 0,
                    'total_sales' => 0.0,
                ],
            ],
        ], 201);
    }

    /**
     * Get detailed client information & sales metrics.
     */
    public function show(int $id)
    {
        $user = User::withCount(['products', 'transactions', 'debts'])
            ->withSum('transactions', 'total_amount')
            ->findOrFail($id);

        $recentTransactions = Transaction::where('user_id', $user->id)
            ->with(['items.product'])
            ->orderBy('created_at', 'desc')
            ->limit(10)
            ->get();

        $todaySales = (float) Transaction::where('user_id', $user->id)
            ->where('created_at', '>=', now()->startOfDay())
            ->sum('total_amount');

        return response()->json([
            'user' => [
                'id' => $user->id,
                'username' => $user->username,
                'full_name' => $user->full_name,
                'email' => $user->email,
                'image_path' => $user->image_path,
                'role' => $user->role,
                'is_active' => (bool) $user->is_active,
                'has_pin' => !empty($user->pin),
                'created_at' => $user->created_at ? $user->created_at->toIso8601String() : null,
                'stats' => [
                    'products_count' => (int) $user->products_count,
                    'transactions_count' => (int) $user->transactions_count,
                    'debts_count' => (int) $user->debts_count,
                    'total_sales' => (float) ($user->transactions_sum_total_amount ?? 0),
                    'today_sales' => $todaySales,
                ],
                'recent_transactions' => $recentTransactions,
            ],
        ]);
    }

    /**
     * Update client account details.
     */
    public function update(Request $request, int $id)
    {
        $user = User::findOrFail($id);

        $validated = $request->validate([
            'full_name' => 'sometimes|required|string|max:100',
            'email' => ['nullable', 'email', 'max:150', Rule::unique('users', 'email')->ignore($user->id)],
            'role' => 'sometimes|string|in:admin,client',
            'is_active' => 'sometimes|boolean',
            'image' => 'nullable|image|mimes:jpeg,png,jpg,webp|max:4096',
            'image_path' => 'nullable|string',
            'remove_image' => 'nullable|boolean',
        ]);

        // Prevent self-demotion if the admin is updating their own role
        if ($request->user()->id === $user->id && isset($validated['role']) && $validated['role'] !== 'admin') {
            return response()->json([
                'message' => 'You cannot remove your own administrator privileges.',
            ], 422);
        }

        if ($request->boolean('remove_image')) {
            $this->deleteStorePhotoIfExists($user->image_path);
            $validated['image_path'] = null;
        } elseif ($request->hasFile('image')) {
            $newPath = $this->handleStorePhotoUpload($request, $user->image_path);
            if ($newPath) {
                $validated['image_path'] = $newPath;
            }
        }

        $user->update($validated);

        return response()->json([
            'message' => 'Client updated successfully',
            'user' => [
                'id' => $user->id,
                'username' => $user->username,
                'full_name' => $user->full_name,
                'email' => $user->email,
                'image_path' => $user->image_path,
                'role' => $user->role,
                'is_active' => (bool) $user->is_active,
                'has_pin' => !empty($user->pin),
            ],
        ]);
    }

    /**
     * Toggle active / inactive status of client.
     */
    public function toggleStatus(Request $request, int $id)
    {
        $user = User::findOrFail($id);

        if ($request->user()->id === $user->id) {
            return response()->json([
                'message' => 'You cannot deactivate your own account.',
            ], 422);
        }

        $user->is_active = !$user->is_active;
        $user->save();

        AuditLogger::log('admin.client.toggle_status', $request, [
            'target_user_id' => $user->id,
            'target_username' => $user->username,
            'is_active' => (bool) $user->is_active,
        ]);

        return response()->json([
            'message' => $user->is_active ? 'Client account activated' : 'Client account deactivated',
            'is_active' => (bool) $user->is_active,
        ]);
    }

    /**
     * Reset client password and/or PIN.
     */
    public function resetCredentials(Request $request, int $id)
    {
        $user = User::findOrFail($id);

        $validated = $request->validate([
            'password' => 'nullable|string|min:4',
            'pin' => 'nullable|string|digits_between:4,6',
        ]);

        if (empty($validated['password']) && !array_key_exists('pin', $validated)) {
            return response()->json([
                'message' => 'Please provide a new password or PIN to update.',
            ], 422);
        }

        $updates = [];
        if (!empty($validated['password'])) {
            $updates['password'] = Hash::make($validated['password']);
        }
        if (array_key_exists('pin', $validated)) {
            $updates['pin'] = !empty($validated['pin']) ? Hash::make($validated['pin']) : null;
        }

        $user->update($updates);

        AuditLogger::log('admin.client.reset_credentials', $request, [
            'target_user_id' => $user->id,
            'target_username' => $user->username,
            'updated_password' => !empty($validated['password']),
            'updated_pin' => array_key_exists('pin', $validated),
        ]);

        return response()->json([
            'message' => 'Credentials updated successfully',
        ]);
    }

    /**
     * Delete a client account and related data.
     */
    public function destroy(Request $request, int $id)
    {
        $user = User::findOrFail($id);

        if ($request->user()->id === $user->id) {
            return response()->json([
                'message' => 'You cannot delete your own administrator account.',
            ], 422);
        }

        // Delete stored store photo if present
        $this->deleteStorePhotoIfExists($user->image_path);

        DB::transaction(function () use ($user) {
            // Delete personal access tokens
            $user->tokens()->delete();

            // Delete debts
            $user->debts()->delete();

            // Delete transaction items and transactions
            foreach ($user->transactions as $tx) {
                $tx->items()->delete();
                $tx->delete();
            }

            // Delete products
            $user->products()->delete();

            // Delete the user
            $user->delete();
        });

        AuditLogger::log('admin.client.deleted', $request, [
            'deleted_user_id' => $user->id,
            'deleted_username' => $user->username,
        ]);

        return response()->json([
            'message' => 'Client account and associated records deleted successfully',
        ]);
    }

    /**
     * Get configured upload disk (R2, S3, or public fallback).
     */
    private function getUploadDisk(): string
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
    private function getDisksToCheck(): array
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
    private function handleStorePhotoUpload(Request $request, ?string $oldImagePath = null): ?string
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
    private function deleteStorePhotoIfExists(?string $imagePath, ?string $disk = null): void
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

    /**
     * Stream store images directly through the API proxy.
     */
    public function serveStoreImage(string $filename)
    {
        $filename = basename($filename);
        if (!preg_match('/^[a-zA-Z0-9_\-\.]+$/', $filename)) {
            abort(404, 'Invalid image name');
        }

        $path = 'stores/' . $filename;
        $headers = [
            'Cache-Control' => 'public, max-age=31536000, immutable',
        ];

        $disksToCheck = $this->getDisksToCheck();
        foreach ($disksToCheck as $diskName) {
            try {
                if (Storage::disk($diskName)->exists($path)) {
                    return Storage::disk($diskName)->response($path, $filename, $headers);
                }
            } catch (\Throwable $e) {
                Log::warning("serveStoreImage could not load [{$path}] from disk [{$diskName}]: " . $e->getMessage());
            }
        }

        abort(404, 'Store image not found');
    }
}

