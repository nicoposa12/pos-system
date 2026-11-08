<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Traits\HandlesStorePhotoUpload;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    use HandlesStorePhotoUpload;
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
                'email' => $user->email,
                'image_path' => $this->normalizeImagePath($user->image_path),
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
            // Strict Terminal Isolation: Scoped strictly to this device's bound user.
            // Cashier terminals cannot be unlocked by the admin PIN.
            $candidates = User::whereNotNull('pin')
                ->where('username', $validated['username'])
                ->get();
        } else {
            // Unscoped PIN entry only permits administrator PIN for global maintenance on unbound devices
            $candidates = User::whereNotNull('pin')
                ->where('role', 'admin')
                ->get();
        }

        $matchedUser = null;
        foreach ($candidates as $user) {
            if ($this->pinMatches($user, $validated['pin'])) {
                $matchedUser = $user;
                break;
            }
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
                'email' => $matchedUser->email,
                'image_path' => $this->normalizeImagePath($matchedUser->image_path),
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
            'pin' => Hash::make($validated['pin']),
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
                'image_path' => $this->normalizeImagePath($user->image_path),
                'role' => $user->role ?? 'client',
                'is_active' => (bool) $user->is_active,
                'has_pin' => !empty($user->pin),
            ],
        ]);
    }

    /**
     * Update current authenticated user profile (business name and/or store photo).
     */
    public function updateProfile(Request $request)
    {
        $user = $request->user();

        if ($request->has('remove_image')) {
            $request->merge([
                'remove_image' => filter_var($request->input('remove_image'), FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE) ?? $request->input('remove_image'),
            ]);
        }

        $validated = $request->validate([
            'full_name' => 'sometimes|string|max:100',
            'email' => ['nullable', 'email', 'max:150', Rule::unique('users', 'email')->ignore($user->id)],
            'image' => 'nullable|image|mimes:jpeg,png,jpg,webp|max:10240',
            'remove_image' => 'nullable|boolean',
        ]);

        if ($request->boolean('remove_image')) {
            $this->deleteStorePhotoIfExists($user->image_path);
            $user->image_path = null;
        } elseif ($request->hasFile('image')) {
            $newPath = $this->handleStorePhotoUpload($request, $user->image_path);
            if ($newPath) {
                $user->image_path = $newPath;
            }
        }

        if (!empty($validated['full_name'])) {
            $user->full_name = $validated['full_name'];
        }
        if (array_key_exists('email', $validated)) {
            $user->email = $validated['email'];
        }

        $user->save();

        return response()->json([
            'message' => 'Profile updated successfully',
            'user' => [
                'id' => $user->id,
                'username' => $user->username,
                'full_name' => $user->full_name,
                'email' => $user->email,
                'image_path' => $this->normalizeImagePath($user->image_path),
                'role' => $user->role ?? 'client',
                'is_active' => (bool) $user->is_active,
                'has_pin' => !empty($user->pin),
            ],
        ]);
    }

    /**
     * Verify the authenticated user's PIN (idle-lock unlock, sensitive action confirmation)
     * without issuing a new token.
     */
    public function verifyPin(Request $request)
    {
        $validated = $request->validate([
            'pin' => 'required|string',
        ]);

        $user = $request->user();

        if (empty($user->pin) || !$this->pinMatches($user, $validated['pin'])) {
            return response()->json(['message' => 'Invalid PIN.'], 401);
        }

        if (!$user->is_active) {
            return response()->json([
                'message' => 'This account has been deactivated. Please contact an administrator.',
            ], 403);
        }

        return response()->json(['message' => 'PIN verified']);
    }

    /**
     * Change the authenticated user's password.
     */
    public function changePassword(Request $request)
    {
        $validated = $request->validate([
            'current_password' => 'required|string',
            'password' => 'required|string|min:6',
        ]);

        $user = $request->user();

        if (!Hash::check($validated['current_password'], $user->password)) {
            throw ValidationException::withMessages([
                'current_password' => ['The current password is incorrect.'],
            ]);
        }

        // The 'hashed' cast on User hashes the new password automatically
        $user->update(['password' => $validated['password']]);

        return response()->json(['message' => 'Password updated successfully']);
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

    /**
     * Checks a PIN against the stored value (bcrypt hash or legacy plaintext).
     * Legacy plaintext PINs are transparently upgraded to a hash on match.
     */
    private function pinMatches(User $user, string $pin): bool
    {
        if (empty($user->pin)) {
            return false;
        }

        // Direct check for legacy plaintext PIN
        if ($user->pin === $pin) {
            // Non-fatal: a failed hash upgrade must never block a valid login
            try {
                $user->pin = Hash::make($pin);
                $user->save();
            } catch (\Throwable $e) {
                $user->pin = $pin;
                Log::warning("PIN hash upgrade failed for user {$user->id}: " . $e->getMessage());
            }
            return true;
        }

        // Check if stored PIN is a valid password hash
        try {
            $info = password_get_info((string) $user->pin);
            return !empty($info['algo']) && Hash::check($pin, $user->pin);
        } catch (\Throwable) {
            return false;
        }
    }
}
