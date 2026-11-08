<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Debt;
use App\Models\Product;
use App\Models\Transaction;
use App\Models\TransactionItem;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class SyncController extends Controller
{
    /**
     * Fast lightweight sync status & change-detection hashes.
     * Allows mobile clients to detect changes in real-time with near-zero latency and bandwidth.
     * Uses one indexed aggregate query per table (user_id, updated_at) instead of a
     * database-backed cache, which cost more round-trips to Neon than it saved.
     */
    public function status(Request $request)
    {
        $userId = $request->user()->id;

        return response()->json([
            'products_version' => $this->versionHash(Product::where('user_id', $userId)),
            'transactions_version' => $this->versionHash(Transaction::where('user_id', $userId)),
            'debts_version' => $this->versionHash(Debt::where('user_id', $userId)),
            'timestamp' => now()->toIso8601String(),
        ]);
    }

    /**
     * Hash of the latest modification time and row count for a scoped query.
     */
    private function versionHash($query): string
    {
        $row = $query->toBase()
            ->selectRaw('MAX(updated_at) as latest, COUNT(*) as total')
            ->first();

        return md5(($row->latest ?? '') . '|' . ($row->total ?? 0));
    }

    /**
     * Batch sync offline transactions from Flutter SQLite to PostgreSQL.
     */
    public function syncOfflineTransactions(Request $request)
    {
        $validated = $request->validate([
            'transactions' => 'required|array',
            'transactions.*.client_id' => 'required', // local sqlite id
            'transactions.*.total_amount' => 'required|numeric',
            'transactions.*.discount' => 'nullable|numeric',
            'transactions.*.cash_received' => 'nullable|numeric',
            'transactions.*.change_amount' => 'nullable|numeric',
            'transactions.*.payment_method' => 'required|string',
            'transactions.*.date' => 'required|string',
            'transactions.*.customer_name' => 'nullable|string',
            'transactions.*.items' => 'required|array',
            'transactions.*.items.*.product_id' => 'required|integer',
            'transactions.*.items.*.quantity' => 'required|integer',
            'transactions.*.items.*.subtotal' => 'required|numeric',
        ]);

        $userId = $request->user()->id;
        $syncedMapping = [];

        // Secure multi-tenant scoping: ensure products belong strictly to this user
        $allProductIds = [];
        foreach ($validated['transactions'] as $tx) {
            foreach ($tx['items'] as $it) {
                $allProductIds[] = $it['product_id'];
            }
        }
        $validProductIds = Product::whereIn('id', array_unique($allProductIds))
            ->where('user_id', $userId)
            ->pluck('id')
            ->flip();

        DB::transaction(function () use ($validated, $userId, $validProductIds, &$syncedMapping) {
            foreach ($validated['transactions'] as $txData) {
                $validItems = array_filter($txData['items'], function ($item) use ($validProductIds) {
                    return isset($validProductIds[$item['product_id']]);
                });

                if (empty($validItems)) {
                    continue;
                }

                // Create transaction
                $tx = Transaction::create([
                    'user_id' => $userId,
                    'total_amount' => $txData['total_amount'],
                    'discount' => $txData['discount'] ?? 0.0,
                    'cash_received' => $txData['cash_received'] ?? 0.0,
                    'change_amount' => $txData['change_amount'] ?? 0.0,
                    'payment_method' => $txData['payment_method'],
                    'date' => $txData['date'],
                ]);

                // Create items & deduct stock
                foreach ($validItems as $item) {
                    TransactionItem::create([
                        'transaction_id' => $tx->id,
                        'product_id' => $item['product_id'],
                        'quantity' => $item['quantity'],
                        'subtotal' => $item['subtotal'],
                    ]);

                    Product::where('id', $item['product_id'])
                        ->where('user_id', $userId)
                        ->decrement('stock', $item['quantity']);
                }

                // If debt or pending
                if (in_array(strtolower($txData['payment_method']), ['debt', 'pending'])) {
                    Debt::create([
                        'user_id' => $userId,
                        'transaction_id' => $tx->id,
                        'customer_name' => !empty($txData['customer_name']) ? $txData['customer_name'] : 'Walk-in Customer',
                        'amount' => $txData['total_amount'],
                        'paid_amount' => $txData['cash_received'] ?? 0.0,
                        'status' => (($txData['cash_received'] ?? 0.0) >= $txData['total_amount']) ? 'paid' : 'pending',
                        'date' => $txData['date'],
                    ]);
                }

                $syncedMapping[] = [
                    'client_id' => $txData['client_id'],
                    'server_id' => $tx->id,
                ];
            }
        });

        return response()->json([
            'message' => 'Batch sync completed successfully',
            'synced' => $syncedMapping,
        ]);
    }

    /**
     * Batch sync offline created/updated products from Flutter SQLite to PostgreSQL.
     */
    public function syncOfflineProducts(Request $request)
    {
        $validated = $request->validate([
            'products' => 'required|array',
            'products.*.client_id' => 'required',
            'products.*.name' => 'required|string|max:255',
            'products.*.price' => 'required|numeric|min:0',
            'products.*.stock' => 'required|integer|min:0',
            'products.*.category' => 'nullable|string|max:100',
            'products.*.barcode' => 'nullable|string|max:100',
            'products.*.variants' => 'nullable',
        ]);

        $userId = $request->user()->id;
        $syncedMapping = [];

        DB::transaction(function () use ($validated, $userId, &$syncedMapping) {
            foreach ($validated['products'] as $pData) {
                // Find existing product by barcode (if non-empty) or by exact name for this user
                $existing = Product::where('user_id', $userId)
                    ->where(function ($q) use ($pData) {
                        if (!empty($pData['barcode'])) {
                            $q->where('barcode', $pData['barcode'])
                              ->orWhere('name', $pData['name']);
                        } else {
                            $q->where('name', $pData['name']);
                        }
                    })
                    ->first();

                if ($existing) {
                    $existing->update([
                        'price' => $pData['price'],
                        'stock' => $pData['stock'],
                        'category' => $pData['category'] ?? $existing->category,
                        'barcode' => $pData['barcode'] ?? $existing->barcode,
                        'variants' => is_string($pData['variants'] ?? null)
                            ? json_decode($pData['variants'], true)
                            : ($pData['variants'] ?? $existing->variants),
                    ]);

                    $syncedMapping[] = [
                        'client_id' => $pData['client_id'],
                        'server_id' => $existing->id,
                        'image_path' => $existing->image_path,
                    ];
                } else {
                    $product = Product::create([
                        'user_id' => $userId,
                        'name' => $pData['name'],
                        'price' => $pData['price'],
                        'stock' => $pData['stock'],
                        'category' => $pData['category'] ?? null,
                        'barcode' => $pData['barcode'] ?? null,
                        'variants' => is_string($pData['variants'] ?? null)
                            ? json_decode($pData['variants'], true)
                            : ($pData['variants'] ?? null),
                    ]);

                    $syncedMapping[] = [
                        'client_id' => $pData['client_id'],
                        'server_id' => $product->id,
                        'image_path' => null,
                    ];
                }
            }
        });

        return response()->json([
            'message' => 'Products batch synced successfully',
            'synced' => $syncedMapping,
        ]);
    }
}
