<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * Regression: legacy plaintext PINs triggered a bcrypt hash upgrade that
 * overflowed the old VARCHAR(10) `pin` column on PostgreSQL -> HTTP 500,
 * leaving the mobile app with no API token so products never reached Neon.
 */
class PinLoginTest extends TestCase
{
    use RefreshDatabase;

    private function makeStoreOwner(): User
    {
        return User::create([
            'username' => 'jicca_test',
            'full_name' => 'Jicca Store',
            'password' => 'secret123',
            'role' => 'client',
            'is_active' => true,
        ]);
    }

    public function test_pin_column_can_hold_bcrypt_hash(): void
    {
        $user = $this->makeStoreOwner();
        $hash = Hash::make('1234');

        DB::table('users')->where('id', $user->id)->update(['pin' => $hash]);

        $this->assertSame($hash, DB::table('users')->where('id', $user->id)->value('pin'));
        $this->assertTrue(Schema::hasColumn('users', 'pin'));
    }

    public function test_legacy_plaintext_pin_logs_in_and_is_upgraded_to_hash(): void
    {
        $user = $this->makeStoreOwner();
        DB::table('users')->where('id', $user->id)->update(['pin' => '1234']);

        $response = $this->postJson('/api/auth/pin-login', [
            'pin' => '1234',
            'username' => 'jicca_test',
        ]);

        $response->assertOk()
            ->assertJsonStructure(['token', 'user' => ['id', 'username']])
            ->assertJsonPath('user.username', 'jicca_test');

        $stored = DB::table('users')->where('id', $user->id)->value('pin');
        $this->assertNotSame('1234', $stored);
        $this->assertTrue(Hash::check('1234', $stored));
    }

    public function test_hashed_pin_logs_in_and_token_can_create_product(): void
    {
        $user = $this->makeStoreOwner();
        DB::table('users')->where('id', $user->id)->update(['pin' => Hash::make('4321')]);

        $token = $this->postJson('/api/auth/pin-login', [
            'pin' => '4321',
            'username' => 'jicca_test',
        ])->assertOk()->json('token');

        $this->withHeader('Authorization', "Bearer {$token}")
            ->postJson('/api/products', ['name' => 'Kopiko', 'price' => 12, 'stock' => 30])
            ->assertCreated();

        $this->assertDatabaseHas('products', ['user_id' => $user->id, 'name' => 'Kopiko']);
    }
}

