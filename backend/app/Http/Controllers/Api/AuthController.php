<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    /**
     * Public self-registration is disabled. Client accounts must be created by an administrator.
     */
    public function register(Request $request)
    {
        return response()->json([
            'message' => 'Public registration is disabled. Client accounts must be created by an administrator.',
        ], 403);
    }

    /**
     * Standard Login via Username and Password.
     */
    public function login(Request $request)
    {
        $validated = $request->validate([
            'username' => 'required|string',
            'password' => 'required|string',
        ]);

        $user = User::where('username', $validated['username'])->first();

        if (!$user || !Hash::check($validated['password'], $user->password)) {
            throw ValidationException::withMessages([
                'username' => ['The provided credentials are incorrect.'],
            ]);
        }

        if (!$user->is_active) {
            throw ValidationException::withMessages([
                'username' => ['This account has been deactivated. Please contact an administrator.'],
            ]);
        }

        // Revoke previous tokens optionally or allow multi-device
        $token = $user->createToken('mobile_pos')->plainTextToken;

        return response()->json([
            'message' => 'Login successful',
            'token' => $token,
            'user' => [
                'id' => $user->id,
                'username' => $user->username,
                'full_name' => $user->full_name,
                'role' => $user->role ?? 'client',
                'is_active' => (bool) $user->is_active,
                'has_pin' => !empty($user->pin),
            ],
        ]);
    }

    /**
     * Fast Quick Login via PIN.
     */
    public function pinLogin(Request $request)
    {
        $validated = $request->validate([
            'pin' => 'required|string',
            'username' => 'nullable|string', // Device-scoped account
        ]);

        if (!empty($validated['username'])) {
            // Scoped strictly to this device's bound user (or admin)
            $matchedUser = User::whereNotNull('pin')
                ->where(function ($q) use ($validated) {
                    $q->where('username', $validated['username'])
                      ->orWhere('role', 'admin');
                })
                ->where('pin', $validated['pin'])
                ->first();
        } else {
            // Unscoped PIN entry only permits administrator PIN for global maintenance
            $matchedUser = User::whereNotNull('pin')
                ->where('role', 'admin')
                ->where('pin', $validated['pin'])
                ->first();
        }

        if (!$matchedUser) {
            return response()->json([
                'message' => 'Invalid PIN.',
            ], 401);
        }

        if (!$matchedUser->is_active) {
            return response()->json([
                'message' => 'This account has been deactivated. Please contact an administrator.',
            ], 403);
        }

        $token = $matchedUser->createToken('mobile_pos')->plainTextToken;

        return response()->json([
            'message' => 'PIN Login successful',
            'token' => $token,
            'user' => [
                'id' => $matchedUser->id,
                'username' => $matchedUser->username,
                'full_name' => $matchedUser->full_name,
                'role' => $matchedUser->role ?? 'client',
                'is_active' => (bool) $matchedUser->is_active,
                'has_pin' => true,
            ],
        ]);
    }

    /**
     * Set or update PIN for the authenticated user.
     */
    public function updatePin(Request $request)
    {
        $validated = $request->validate([
            'pin' => 'required|string|digits_between:4,6',
        ]);

        $request->user()->update([
            'pin' => $validated['pin'],
        ]);

        return response()->json([
            'message' => 'PIN updated successfully',
        ]);
    }

    /**
     * Get current authenticated user profile.
     */
    public function me(Request $request)
    {
        $user = $request->user();

        return response()->json([
            'user' => [
                'id' => $user->id,
                'username' => $user->username,
                'full_name' => $user->full_name,
                'email' => $user->email,
                'role' => $user->role ?? 'client',
                'is_active' => (bool) $user->is_active,
                'has_pin' => !empty($user->pin),
            ],
        ]);
    }

    /**
     * Logout and revoke current access token.
     */
    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json([
            'message' => 'Logged out successfully',
        ]);
    }
}
