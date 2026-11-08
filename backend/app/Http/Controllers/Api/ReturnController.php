<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Product;
use App\Models\ProductReturn;
use App\Models\Transaction;
use App\Services\AuditLogger;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ReturnController extends Controller
{
    /**
     * List product returns for the authenticated store.
     */
    public function index(Request $request)
    {
        $returns = ProductReturn::where('user_id', $request->user()->id)
            ->with('product:id,name')
            ->latest('date')
            ->get()
            ->map(fn (ProductReturn $r) => $this->present($r));

        return response()->json(['returns' => $returns]);
    }

    /**
     * Record a product return for a transaction and restore inventory atomically.
     */
    public function store(Request $request, Transaction $transaction)
    {
        $userId = $request->user()->id;
        if ($transaction->user_id !== $userId) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $validated = $request->validate([
            'product_id' => 'required|integer',
            'quantity' => 'required|integer|min:1',
            'reason' => 'nullable|string|max:500',
        ]);

        return DB::transaction(function () use ($validated, $transaction, $userId, $request) {
            $purchased = (int) $transaction->items()
                ->where('product_id', $validated['product_id'])
                ->sum('quantity');

            if ($purchased === 0) {
                return response()->json(['message' => 'This product is not part of the transaction.'], 422);
            }

            $alreadyReturned = (int) ProductReturn::where('transaction_id', $transaction->id)
                ->where('product_id', $validated['product_id'])
                ->lockForUpdate()
                ->sum('quantity');

            if ($validated['quantity'] > $purchased - $alreadyReturned) {
                return response()->json([
                    'message' => 'Return quantity exceeds the remaining purchased quantity ('
                        . max(0, $purchased - $alreadyReturned) . ').',
                ], 422);
            }

            $return = ProductReturn::create([
                'user_id' => $userId,
                'transaction_id' => $transaction->id,
                'product_id' => $validated['product_id'],
                'quantity' => $validated['quantity'],
                'reason' => $validated['reason'] ?? null,
                'date' => now(),
            ]);

            Product::where('id', $validated['product_id'])
                ->where('user_id', $userId)
                ->increment('stock', $validated['quantity']);

            AuditLogger::log('transaction.return', $request, [
                'transaction_id' => $transaction->id,
                'product_id' => $validated['product_id'],
                'quantity' => $validated['quantity'],
            ]);

            $return->load('product:id,name,stock');

            return response()->json([
                'message' => 'Return processed and stock restored',
                'return' => $this->present($return),
                'product_stock' => $return->product?->stock,
            ], 201);
        });
    }

    private function present(ProductReturn $r): array
    {
        return [
            'id' => $r->id,
            'transaction_id' => $r->transaction_id,
            'product_id' => $r->product_id,
            'product_name' => $r->product?->name,
            'quantity' => $r->quantity,
            'reason' => $r->reason,
            'date' => $r->date?->toIso8601String(),
        ];
    }
}

