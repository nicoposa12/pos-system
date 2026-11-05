<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Debt;
use App\Models\Product;
use App\Models\Transaction;
use App\Models\TransactionItem;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class TransactionController extends Controller
{
    /**
     * List all transactions with items.
     */
    public function index(Request $request)
    {
        $query = $request->user()->transactions()
            ->with(['items.product', 'debt'])
            ->latest('date');

        if ($request->boolean('all')) {
            return response()->json([
                'data' => $query->get(),
            ]);
        }

        $perPage = (int) $request->input('per_page', 50);
        $transactions = $query->paginate($perPage);

        return response()->json($transactions);
    }

    /**
     * Complete a POS sale transaction atomically.
     */
    public function store(Request $request)
    {
        $validated = $request->validate([
            'total_amount' => 'required|numeric|min:0',
            'discount' => 'nullable|numeric|min:0',
            'cash_received' => 'nullable|numeric|min:0',
            'change_amount' => 'nullable|numeric|min:0',
            'payment_method' => 'required|string',
            'date' => 'nullable|date',
            'customer_name' => 'nullable|string', // required if debt
            'items' => 'required|array|min:1',
            'items.*.product_id' => 'required|exists:products,id',
            'items.*.quantity' => 'required|integer|min:1',
            'items.*.subtotal' => 'required|numeric|min:0',
        ]);

        $userId = $request->user()->id;

        return DB::transaction(function () use ($validated, $userId) {
            // 1. Create Transaction
            $transaction = Transaction::create([
                'user_id' => $userId,
                'total_amount' => $validated['total_amount'],
                'discount' => $validated['discount'] ?? 0.0,
                'cash_received' => $validated['cash_received'] ?? 0.0,
                'change_amount' => $validated['change_amount'] ?? 0.0,
                'payment_method' => $validated['payment_method'],
                'date' => $validated['date'] ?? now(),
            ]);

            // 2. Insert items and decrement stock
            foreach ($validated['items'] as $itemData) {
                TransactionItem::create([
                    'transaction_id' => $transaction->id,
                    'product_id' => $itemData['product_id'],
                    'quantity' => $itemData['quantity'],
                    'subtotal' => $itemData['subtotal'],
                ]);

                // Decrement stock
                Product::where('id', $itemData['product_id'])
                    ->where('user_id', $userId)
                    ->decrement('stock', $itemData['quantity']);
            }

            // 3. If payment method is debt or pending, create debt record
            if (in_array(strtolower($validated['payment_method']), ['debt', 'pending'])) {
                Debt::create([
                    'user_id' => $userId,
                    'transaction_id' => $transaction->id,
                    'customer_name' => !empty($validated['customer_name']) ? $validated['customer_name'] : 'Walk-in Customer',
                    'amount' => $validated['total_amount'],
                    'paid_amount' => $validated['cash_received'] ?? 0.0,
                    'status' => (($validated['cash_received'] ?? 0.0) >= $validated['total_amount']) ? 'paid' : 'pending',
                    'date' => $validated['date'] ?? now(),
                ]);
            }

            $transaction->load(['items.product', 'debt']);

            return response()->json([
                'message' => 'Transaction completed successfully',
                'transaction' => $transaction,
            ], 201);
        });
    }

    /**
     * Show single transaction detail.
     */
    public function show(Request $request, Transaction $transaction)
    {
        if ($transaction->user_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $transaction->load(['items.product', 'debt']);

        return response()->json(['transaction' => $transaction]);
    }

    /**
     * Mark a pending transaction as paid.
     */
    public function markPaid(Request $request, Transaction $transaction)
    {
        if ($transaction->user_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $validated = $request->validate([
            'payment_method' => 'required|string',
            'cash_received' => 'nullable|numeric|min:0',
            'change_amount' => 'nullable|numeric|min:0',
        ]);

        $cashReceived = $validated['cash_received'] ?? $transaction->total_amount;
        $isFullyPaid = $cashReceived >= $transaction->total_amount;

        $transaction->update([
            'payment_method' => $isFullyPaid ? $validated['payment_method'] : 'pending',
            'cash_received' => $cashReceived,
            'change_amount' => $validated['change_amount'] ?? 0.0,
        ]);

        if ($transaction->debt) {
            $transaction->debt->update([
                'paid_amount' => $cashReceived,
                'status' => $isFullyPaid ? 'paid' : 'pending',
            ]);
        }

        $transaction->load(['items.product', 'debt']);

        return response()->json([
            'message' => $isFullyPaid ? 'Transaction marked as paid successfully' : 'Payment recorded successfully',
            'transaction' => $transaction,
        ]);
    }
}
