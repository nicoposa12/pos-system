<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\DebtController;
use App\Http\Controllers\Api\ProductController;
use App\Http\Controllers\Api\SyncController;
use App\Http\Controllers\Api\TransactionController;
use Illuminate\Support\Facades\Route;

// Public routes
Route::prefix('auth')->group(function () {
    Route::get('/ping', function () {
        return response()->json(['status' => 'online', 'timestamp' => now()->toIso8601String()]);
    });
    Route::post('/register', [AuthController::class, 'register']);
    Route::post('/login', [AuthController::class, 'login']);
    Route::post('/pin-login', [AuthController::class, 'pinLogin']);
});

// Protected routes (Sanctum)
Route::middleware('auth:sanctum')->group(function () {
    // Auth & Profile
    Route::prefix('auth')->group(function () {
        Route::get('/me', [AuthController::class, 'me']);
        Route::post('/pin', [AuthController::class, 'updatePin']);
        Route::post('/logout', [AuthController::class, 'logout']);
    });

    // Products
    Route::get('/products/barcode/{barcode}', [ProductController::class, 'byBarcode']);
    Route::apiResource('products', ProductController::class);

    // Transactions (POS Checkout)
    Route::post('/transactions/{transaction}/mark-paid', [TransactionController::class, 'markPaid']);
    Route::apiResource('transactions', TransactionController::class)->only(['index', 'store', 'show']);

    // Debts
    Route::get('/debts', [DebtController::class, 'index']);
    Route::post('/debts', [DebtController::class, 'store']);
    Route::post('/debts/{debt}/pay', [DebtController::class, 'pay']);

    // Offline Batch Sync
    Route::post('/sync', [SyncController::class, 'syncOfflineTransactions']);
});
