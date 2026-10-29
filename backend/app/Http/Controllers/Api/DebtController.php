<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Debt;
use Illuminate\Http\Request;

class DebtController extends Controller
{
    /**
     * List all debts for user.
     */
    public function index(Request $request)
    {
        $query = $request->user()->debts()->with('transaction');

        if ($request->filled('status')) {
            $query->where('status', $request->input('status'));
        }

        $debts = $query->latest('date')->get();

        return response()->json(['debts' => $debts]);
    }

    /**
     * Create a new debt record.
     */
    public function store(Request $request)
    {
        $validated = $request->validate([
            'customer_name' => 'required|string|max:255',
            'amount' => 'required|numeric|min:0',
            'paid_amount' => 'nullable|numeric|min:0',
            'date' => 'nullable|date',
        ]);

        $paid = $validated['paid_amount'] ?? 0.0;
        $status = ($paid >= $validated['amount']) ? 'paid' : 'pending';

        $debt = $request->user()->debts()->create([
            'customer_name' => $validated['customer_name'],
            'amount' => $validated['amount'],
            'paid_amount' => $paid,
            'status' => $status,
            'date' => $validated['date'] ?? now(),
        ]);

        return response()->json([
            'message' => 'Debt recorded successfully',
            'debt' => $debt,
        ], 201);
    }

    /**
     * Record payment toward a debt.
     */
    public function pay(Request $request, Debt $debt)
    {
        if ($debt->user_id !== $request->user()->id) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $validated = $request->validate([
            'amount' => 'required|numeric|min:0.01',
        ]);

        $newPaidAmount = $debt->paid_amount + $validated['amount'];
        $status = ($newPaidAmount >= $debt->amount) ? 'paid' : 'pending';

        $debt->update([
            'paid_amount' => $newPaidAmount,
            'status' => $status,
        ]);

        return response()->json([
            'message' => 'Debt payment recorded',
            'debt' => $debt,
        ]);
    }
}
