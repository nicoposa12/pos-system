<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class ProductProfitTrackingTest extends TestCase
{
    use RefreshDatabase;

    private function createStoreUser(string $username = 'profitstore'): User
    {
        return User::create([
            'username' => $username,
            'full_name' => 'Profit Test Store',
            'email' => "{$username}@example.com",
            'password' => Hash::make('password123'),
            'role' => 'client',
            'is_active' => true,
        ]);
    }

    public function test_product_create_and_update_persist_and_clear_cost_price(): void
    {
        $user = $this->createStoreUser();

        $createRes = $this->actingAs($user, 'sanctum')->postJson('/api/products', [
            'name' => 'Premium Coffee',
            'category' => 'Beverages',
            'price' => 120.00,
            'cost_price' => 75.50,
            'stock' => 25,
            'unit' => 'pack',
        ]);

        $createRes->assertStatus(201)
            ->assertJsonPath('product.price', 120)
            ->assertJsonPath('product.cost_price', 75.5);

        $productId = $createRes->json('product.id');

        // Partial update without cost_price must preserve existing cost_price
        $partialRes = $this->actingAs($user, 'sanctum')->putJson("/api/products/{$productId}", [
            'stock' => 30,
        ]);
        $partialRes->assertStatus(200)
            ->assertJsonPath('product.cost_price', 75.5);

        // Explicit null clears cost_price safely
        $clearRes = $this->actingAs($user, 'sanctum')->putJson("/api/products/{$productId}", [
            'cost_price' => null,
        ]);
        $clearRes->assertStatus(200)
            ->assertJsonPath('product.cost_price', null);

        // Negative cost_price must be rejected
        $invalidRes = $this->actingAs($user, 'sanctum')->postJson('/api/products', [
            'name' => 'Bad Product',
            'price' => 50,
            'cost_price' => -10,
            'stock' => 5,
        ]);
        $invalidRes->assertStatus(422);

        // Updating a legacy product (cost_price = null) to set cost_price persists on re-fetch
        $setAgainRes = $this->actingAs($user, 'sanctum')->putJson("/api/products/{$productId}", [
            'name' => 'Premium Coffee',
            'price' => 123.36,
            'cost_price' => 90.25,
            'stock' => 17.5,
            'unit' => 'pcs',
        ]);
        $setAgainRes->assertStatus(200)
            ->assertJsonPath('product.cost_price', 90.25);

        $indexRes = $this->actingAs($user, 'sanctum')->getJson('/api/products');
        $indexRes->assertStatus(200)
            ->assertJsonPath('products.0.cost_price', 90.25);
    }

    public function test_checkout_snapshots_unit_cost_and_preserves_history_when_cost_changes(): void
    {
        $user = $this->createStoreUser('historystore');

        $product = Product::create([
            'user_id' => $user->id,
            'name' => 'Jasmine Rice',
            'category' => 'Grains',
            'price' => 58.00,
            'cost_price' => 44.00,
            'stock' => 50.0,
            'unit' => 'kg',
        ]);

        // Sell 2.5 kg at ₱58/kg (subtotal ₱145, cost ₱44/kg)
        $txRes = $this->actingAs($user, 'sanctum')->postJson('/api/transactions', [
            'total_amount' => 145.00,
            'discount' => 0,
            'cash_received' => 150.00,
            'change_amount' => 5.00,
            'payment_method' => 'cash',
            'items' => [
                [
                    'product_id' => $product->id,
                    'quantity' => 2.5,
                    'subtotal' => 145.00,
                ],
            ],
        ]);

        $txRes->assertStatus(201)
            ->assertJsonPath('transaction.items.0.unit_cost', 44);

        $txId = $txRes->json('transaction.id');

        // Supplier raises cost price to ₱52 later
        $this->actingAs($user, 'sanctum')->putJson("/api/products/{$product->id}", [
            'cost_price' => 52.00,
        ])->assertStatus(200);

        // Historical transaction item MUST still hold snapshotted unit_cost = 44
        $showRes = $this->actingAs($user, 'sanctum')->getJson("/api/transactions/{$txId}");
        $showRes->assertStatus(200)
            ->assertJsonPath('transaction.items.0.unit_cost', 44)
            ->assertJsonPath('transaction.items.0.product.cost_price', 52);
    }

    public function test_checkout_snapshots_variant_cost_price_with_base_fallback(): void
    {
        $user = $this->createStoreUser('variantstore');

        $product = Product::create([
            'user_id' => $user->id,
            'name' => 'Iced Tea',
            'category' => 'Drinks',
            'price' => 30.00,
            'cost_price' => 18.00,
            'stock' => 40,
            'unit' => 'pcs',
            'variants' => [
                ['name' => 'Small', 'price' => 25.00, 'cost_price' => 12.00, 'stock' => 20],
                ['name' => 'Promo', 'price' => 25.00, 'cost_price' => 15.50, 'stock' => 10],
                ['name' => 'Large', 'price' => 45.00, 'stock' => 10], // no variant cost -> falls back to base 18
            ],
        ]);

        $res = $this->actingAs($user, 'sanctum')->postJson('/api/transactions', [
            'total_amount' => 95.00,
            'discount' => 0,
            'cash_received' => 100.00,
            'change_amount' => 5.00,
            'payment_method' => 'cash',
            'items' => [
                [
                    'product_id' => $product->id,
                    'variant_name' => 'Promo',
                    'quantity' => 1,
                    'subtotal' => 25.00,
                ],
                [
                    'product_id' => $product->id,
                    'variant_name' => 'Small',
                    'quantity' => 1,
                    'subtotal' => 25.00,
                ],
                [
                    'product_id' => $product->id,
                    'variant_name' => 'Large',
                    'quantity' => 1,
                    'subtotal' => 45.00,
                ],
            ],
        ]);

        $res->assertStatus(201);
        $items = $res->json('transaction.items');
        $this->assertEquals(15.5, (float) $items[0]['unit_cost']);
        $this->assertEquals(12.0, (float) $items[1]['unit_cost']);
        $this->assertEquals(18.0, (float) $items[2]['unit_cost']);
    }

    public function test_offline_sync_persists_cost_price_and_snapshots_unit_cost(): void
    {
        $user = $this->createStoreUser('syncstore');

        $syncProdRes = $this->actingAs($user, 'sanctum')->postJson('/api/sync/products', [
            'products' => [
                [
                    'client_id' => 1,
                    'name' => 'Synced Soda',
                    'price' => 25.00,
                    'cost_price' => 17.50,
                    'stock' => 20,
                    'unit' => 'pcs',
                ],
            ],
        ]);

        $syncProdRes->assertStatus(200);
        $serverId = $syncProdRes->json('synced.0.server_id');
        $product = Product::findOrFail($serverId);
        $this->assertEquals(17.5, (float) $product->cost_price);

        $syncTxRes = $this->actingAs($user, 'sanctum')->postJson('/api/sync', [
            'transactions' => [
                [
                    'client_id' => 10,
                    'total_amount' => 50.00,
                    'discount' => 0,
                    'cash_received' => 50.00,
                    'change_amount' => 0,
                    'payment_method' => 'cash',
                    'date' => now()->toIso8601String(),
                    'items' => [
                        [
                            'product_id' => $serverId,
                            'quantity' => 2,
                            'subtotal' => 50.00,
                        ],
                    ],
                ],
            ],
        ]);

        $syncTxRes->assertStatus(200);
        $txServerId = $syncTxRes->json('synced.0.server_id');
        $this->assertDatabaseHas('transaction_items', [
            'transaction_id' => $txServerId,
            'product_id' => $serverId,
            'unit_cost' => 17.50,
        ]);
    }
}
