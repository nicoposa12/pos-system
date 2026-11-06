<?php

namespace App\Services;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class AuditLogger
{
    /**
     * Log a sensitive security, operational, or financial event.
     */
    public static function log(string $action, Request $request, array $details = []): void
    {
        $user = $request->user();

        Log::channel('daily')->info("[AUDIT] {$action}", [
            'action' => $action,
            'user_id' => $user?->id,
            'username' => $user?->username,
            'role' => $user?->role,
            'ip' => $request->ip(),
            'user_agent' => $request->userAgent(),
            'details' => $details,
            'timestamp' => now()->toIso8601String(),
        ]);
    }
}

