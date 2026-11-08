<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Debt;
use App\Models\Product;
use App\Models\Transaction;
use App\Models\TransactionItem;
use App\Services\AuditLogger;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class TransactionController extends Controller
{
    /**
     * List all transactions with items.
     */
    public function index(Request $request)
    {
        $query = $request->user()->transactions()
            ->with(['items.product:id,name,category,stock', 'debt'])
            ->latest('date');

        // Incremental Delta Sync: return only records modified after the specified timestamp
        if ($request->filled('since')) {
            $query->where('updated_at', '>', $request->input('since'));
        }

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
        $userId = $request->user()->id;

        $validated = $request->validate([
            'total_amount' => 'required|numeric|min:0',
            'discount' => 'nullable|numeric|min:0',
            'cash_received' => 'nullable|numeric|min:0',
            'change_amount' => 'nullable|numeric|min:0',
            'payment_method' => 'required|string',
            'date' => 'nullable|date',
            'customer_name' => 'nullable|string', // required if debt
            'items' => 'required|array|min:1',
            'items.*.product_id' => [
                'required',
                'integer',
                Rule::exists('products', 'id')->where('user_id', $userId),
            ],
            'items.*.quantity' => 'required|integer|min:1',
            'items.*.subtotal' => 'required|numeric|min:0',
        ]);

        return DB::transaction(function () use ($validated, $userId) {
            // Price integrity & tampering verification
            $productIds = collect($validated['items'])->pluck('product_id')->all();
            $products = Product::whereIn('id', $productIds)
                ->where('user_id', $userId)
                ->get()
                ->keyBy('id');

            $calculatedItemsTotal = 0.0;
            foreach ($validated['items'] as $itemData) {
                $product = $products->get($itemData['product_id']);
                if (!$product) {
                    abort(422, 'Product not found or unauthorized.');
                }

                $validPrices = [(float) $product->price];
                if (!empty($product->variants) && is_array($product->variants)) {
                    foreach ($product->variants as $variant) {
                        if (isset($variant['price'])) {
                            $validPrices[] = (float) $variant['price'];
                        }
                    }
                }

                $quantity = (int) $itemData['quantity'];
                $unitPrice = (float) $itemData['subtotal'] / $quantity;

                // Check if unitPrice matches base price or any variant price within 5 cents tolerance
                $matchedPrice = false;
                foreach ($validPrices as $vp) {
                    if (abs($vp - $unitPrice) < 0.05) {
                        $matchedPrice = true;
                        break;
                    }
                }

                if (!$matchedPrice) {
                    return response()->json([
                        'message' => "Price manipulation detected for product: {$product->name}.",
                    ], 422);
                }

                $calculatedItemsTotal += (float) $itemData['subtotal'];
            }

            $discount = (float) ($validated['discount'] ?? 0.0);
            $expectedTotal = max(0.0, round($calculatedItemsTotal - $discount, 2));

            if (abs($expectedTotal - (float) $validated['total_amount']) > 0.05) {
                return response()->json([
                    'message' => 'Price integrity check failed. The submitted total does not match store items and discount.',
                    'calculated_total' => $expectedTotal,
                    'submitted_total' => (float) $validated['total_amount'],
                ], 422);
            }

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

            $transaction->load(['items.product:id,name,category,stock', 'debt']);

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

        $transaction->load(['items.product:id,name,category,stock', 'debt']);

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

        AuditLogger::log('transaction.mark_paid', $request, [
            'transaction_id' => $transaction->id,
            'total_amount' => (float) $transaction->total_amount,
            'cash_received' => (float) $cashReceived,
            'payment_method' => $validated['payment_method'],
            'is_fully_paid' => $isFullyPaid,
        ]);

        $transaction->load(['items.product:id,name,category,stock', 'debt']);

        return response()->json([
            'message' => $isFullyPaid ? 'Transaction marked as paid successfully' : 'Payment recorded successfully',
            'transaction' => $transaction,
        ]);
    }
}
