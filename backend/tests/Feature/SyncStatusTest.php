<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class SyncStatusTest extends TestCase
{
    use RefreshDatabase;

    public function test_sync_status_single_query_returns_consistent_hashes_and_detects_changes(): void
    {
        $user = User::create([
            'username' => 'syncstatususer',
            'full_name' => 'Sync Status Store',
            'email' => 'syncstatus@example.com',
            'password' => Hash::make('password123'),
            'role' => 'client',
            'is_active' => true,
        ]);

        $initial = $this->actingAs($user, 'sanctum')->getJson('/api/sync/status');
        $initial->assertOk()
            ->assertJsonStructure([
                'products_version',
                'transactions_version',
                'debts_version',
                'timestamp',
            ]);

        $initialProductsHash = $initial->json('products_version');
        $initialTxHash = $initial->json('transactions_version');

        // Repeated call with no changes produces identical hashes
        $same = $this->actingAs($user, 'sanctum')->getJson('/api/sync/status');
        $same->assertOk()
            ->assertJsonPath('products_version', $initialProductsHash)
            ->assertJsonPath('transactions_version', $initialTxHash);

        // Creating a product changes only products_version
        Product::create([
            'user_id' => $user->id,
            'name' => 'Hash Check Item',
            'price' => 20.0,
            'stock' => 10,
            'unit' => 'pcs',
        ]);

        $afterProduct = $this->actingAs($user, 'sanctum')->getJson('/api/sync/status');
        $afterProduct->assertOk();
        $this->assertNotSame($initialProductsHash, $afterProduct->json('products_version'));
        $this->assertSame($initialTxHash, $afterProduct->json('transactions_version'));
    }
}
