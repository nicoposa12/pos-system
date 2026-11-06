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
        ]);

        $user = User::create([
            'username' => $validated['username'],
            'full_name' => $validated['full_name'],
            'email' => $validated['email'] ?? null,
            'password' => Hash::make($validated['password']),
            'pin' => !empty($validated['pin']) ? Hash::make($validated['pin']) : null,
            'role' => $validated['role'] ?? 'client',
            'is_active' => $validated['is_active'] ?? true,
        ]);

        return response()->json([
            'message' => 'Account created successfully',
            'user' => [
                'id' => $user->id,
                'username' => $user->username,
                'full_name' => $user->full_name,
                'email' => $user->email,
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
        ]);

        // Prevent self-demotion if the admin is updating their own role
        if ($request->user()->id === $user->id && isset($validated['role']) && $validated['role'] !== 'admin') {
            return response()->json([
                'message' => 'You cannot remove your own administrator privileges.',
            ], 422);
        }

        $user->update($validated);

        return response()->json([
            'message' => 'Client updated successfully',
            'user' => [
                'id' => $user->id,
                'username' => $user->username,
                'full_name' => $user->full_name,
                'email' => $user->email,
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
}

