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
     * Register a new user and return a Sanctum token.
     */
    public function register(Request $request)
    {
        $validated = $request->validate([
            'username' => 'required|string|max:50|unique:users,username',
            'full_name' => 'required|string|max:100',
            'password' => 'required|string|min:4',
            'pin' => 'nullable|string|digits_between:4,6',
            'email' => 'nullable|email|unique:users,email',
        ]);

        $user = User::create([
            'username' => $validated['username'],
            'full_name' => $validated['full_name'],
            'password' => Hash::make($validated['password']),
            'pin' => $validated['pin'] ?? null,
            'email' => $validated['email'] ?? null,
        ]);

        $token = $user->createToken('mobile_pos')->plainTextToken;

        return response()->json([
            'message' => 'User registered successfully',
            'token' => $token,
            'user' => [
                'id' => $user->id,
                'username' => $user->username,
                'full_name' => $user->full_name,
                'has_pin' => !empty($user->pin),
            ],
        ], 201);
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

        // Revoke previous tokens optionally or allow multi-device
        $token = $user->createToken('mobile_pos')->plainTextToken;

        return response()->json([
            'message' => 'Login successful',
            'token' => $token,
            'user' => [
                'id' => $user->id,
                'username' => $user->username,
                'full_name' => $user->full_name,
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
            'username' => 'nullable|string', // optional if multiple accounts on device
        ]);

        $query = User::whereNotNull('pin');
        if (!empty($validated['username'])) {
            $query->where('username', $validated['username']);
        }

        $users = $query->get();
        $matchedUser = null;

        foreach ($users as $user) {
            if ($user->pin === $validated['pin']) {
                $matchedUser = $user;
                break;
            }
        }

        if (!$matchedUser) {
            return response()->json([
                'message' => 'Invalid PIN.',
            ], 401);
        }

        $token = $matchedUser->createToken('mobile_pos')->plainTextToken;

        return response()->json([
            'message' => 'PIN Login successful',
            'token' => $token,
            'user' => [
                'id' => $matchedUser->id,
                'username' => $matchedUser->username,
                'full_name' => $matchedUser->full_name,
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
