<?php

use App\Http\Controllers\Api\AdminController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\DebtController;
use App\Http\Controllers\Api\ProductController;
use App\Http\Controllers\Api\ReturnController;
use App\Http\Controllers\Api\SyncController;
use App\Http\Controllers\Api\TransactionController;
use Illuminate\Support\Facades\Route;

// Public routes
Route::prefix('auth')->group(function () {
    Route::get('/ping', function () {
        return response()->json(['status' => 'online', 'timestamp' => now()->toIso8601String()]);
    });
    Route::post('/register', [AuthController::class, 'register']);
    Route::post('/login', [AuthController::class, 'login'])->middleware('throttle:auth-limiter');
    Route::post('/pin-login', [AuthController::class, 'pinLogin'])->middleware('throttle:auth-limiter');
});

// Public App Version & Auto-Update Manifest
Route::get('/app/version', function () {
    $windowsVersion = env('WINDOWS_APP_VERSION', '1.0.3');
    $defaultDownloadUrl = env(
        'WINDOWS_DOWNLOAD_URL',
        "https://github.com/nicoposa12/pos-system/releases/download/v{$windowsVersion}/TindaKo-Setup-v{$windowsVersion}.exe"
    );

    return response()->json([
        'windows' => [
            'version' => $windowsVersion,
            'build_number' => (int) env('WINDOWS_BUILD_NUMBER', 4),
            'download_url' => $defaultDownloadUrl,
            'release_notes' => env('WINDOWS_RELEASE_NOTES', 'TindaKo v1.0.3 with accurate real-time product return calculations, dynamic balance updates, and enhanced receipt workflows.'),
            'force_update' => false,
        ],
        'android' => [
            'version' => env('ANDROID_APP_VERSION', '1.0.3'),
            'build_number' => (int) env('ANDROID_BUILD_NUMBER', 4),
        ],
    ]);
});

// Public image proxy route (allows mobile and web apps to stream product and store images directly through API)
Route::get('/media/products/{filename}', [ProductController::class, 'serveImage']);
Route::get('/media/stores/{filename}', [AdminController::class, 'serveStoreImage']);

// Protected routes (Sanctum)
Route::middleware('auth:sanctum')->group(function () {
    // Auth & Profile
    Route::prefix('auth')->group(function () {
        Route::get('/me', [AuthController::class, 'me']);
        Route::post('/profile', [AuthController::class, 'updateProfile']);
        Route::post('/pin', [AuthController::class, 'updatePin']);
        Route::post('/verify-pin', [AuthController::class, 'verifyPin'])->middleware('throttle:auth-limiter');
        Route::post('/password', [AuthController::class, 'changePassword'])->middleware('throttle:auth-limiter');
        Route::post('/logout', [AuthController::class, 'logout']);
    });

    // Products
    Route::get('/products/barcode/{barcode}', [ProductController::class, 'byBarcode']);
    Route::apiResource('products', ProductController::class);

    // Transactions (POS Checkout)
    Route::post('/transactions/{transaction}/mark-paid', [TransactionController::class, 'markPaid']);
    Route::post('/transactions/{transaction}/returns', [ReturnController::class, 'store']);
    Route::apiResource('transactions', TransactionController::class)->only(['index', 'store', 'show']);

    // Product Returns
    Route::get('/returns', [ReturnController::class, 'index']);

    // Debts
    Route::get('/debts', [DebtController::class, 'index']);
    Route::post('/debts', [DebtController::class, 'store']);
    Route::post('/debts/{debt}/pay', [DebtController::class, 'pay']);

    // Real-Time Sync Status & one-time upload of legacy offline (SQLite) data
    Route::get('/sync/status', [SyncController::class, 'status']);
    Route::post('/sync', [SyncController::class, 'syncOfflineTransactions']);
    Route::post('/sync/products', [SyncController::class, 'syncOfflineProducts']);

    // Admin Client Management
    Route::middleware('admin')->prefix('admin')->group(function () {
        Route::get('/clients', [AdminController::class, 'index']);
        Route::post('/clients', [AdminController::class, 'store']);
        Route::get('/clients/{id}', [AdminController::class, 'show']);
        Route::put('/clients/{id}', [AdminController::class, 'update']);
        Route::patch('/clients/{id}/toggle-status', [AdminController::class, 'toggleStatus']);
        Route::post('/clients/{id}/reset-credentials', [AdminController::class, 'resetCredentials']);
        Route::delete('/clients/{id}', [AdminController::class, 'destroy']);
    });
});
