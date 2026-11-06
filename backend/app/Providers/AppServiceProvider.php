<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Rate limiter for login & pin-login to prevent brute-force attacks
        RateLimiter::for('auth-limiter', function (Request $request) {
            $identifier = $request->input('username') ?? $request->ip();
            return Limit::perMinute(5)->by($identifier . '|' . $request->ip())->response(function () {
                return response()->json([
                    'message' => 'Too many login attempts. Please wait 1 minute before trying again.',
                ], 429);
            });
        });
    }
}
