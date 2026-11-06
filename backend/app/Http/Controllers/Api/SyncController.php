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
     */
    public function status(Request $request)
    {
        $userId = $request->user()->id;

        $latestProduct = Product::where('user_id', $userId)->latest('updated_at')->first(['updated_at']);
        $productCount = Product::where('user_id', $userId)->count();

        $latestTx = Transaction::where('user_id', $userId)->latest('updated_at')->first(['updated_at']);
        $txCount = Transaction::where('user_id', $userId)->count();

        $latestDebt = Debt::where('user_id', $userId)->latest('updated_at')->first(['updated_at']);
        $debtCount = Debt::where('user_id', $userId)->count();

        $productsVersion = md5(($latestProduct?->updated_at?->toIso8601String() ?? '') . '|' . $productCount);
        $transactionsVersion = md5(($latestTx?->updated_at?->toIso8601String() ?? '') . '|' . $txCount);
        $debtsVersion = md5(($latestDebt?->updated_at?->toIso8601String() ?? '') . '|' . $debtCount);

        return response()->json([
            'products_version' => $productsVersion,
            'transactions_version' => $transactionsVersion,
            'debts_version' => $debtsVersion,
            'timestamp' => now()->toIso8601String(),
        ]);
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
}
