<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SyncOfflineProductsTest extends TestCase
{
    use RefreshDatabase;

    public function test_guest_cannot_sync_products(): void
    {
        $response = $this->postJson('/api/sync/products', [
            'products' => [],
        ]);

        $response->assertStatus(401);
    }

    public function test_authenticated_user_can_sync_offline_products(): void
    {
        $user = User::create([
            'username' => 'jiccastore_' . uniqid(),
            'full_name' => 'Jicca Dela Cruz',
            'password' => 'secret123',
            'role' => 'client',
            'is_active' => true,
        ]);

        $payload = [
            'products' => [
                [
                    'client_id' => 101,
                    'name' => 'fgd',
                    'price' => 12.00,
                    'stock' => 21,
                    'category' => 'Personal Care',
                    'barcode' => 'BAR-101',
                ],
                [
                    'client_id' => 102,
                    'name' => 'fghfhg',
                    'price' => 23.00,
                    'stock' => 134,
                    'category' => 'Drinks',
                    'barcode' => null,
                ],
            ],
        ];

        $response = $this->actingAs($user, 'sanctum')->postJson('/api/sync/products', $payload);

        $response->assertStatus(200)
            ->assertJsonStructure([
                'message',
                'synced' => [
                    '*' => ['client_id', 'server_id', 'image_path'],
                ],
            ]);

        $this->assertDatabaseHas('products', [
            'user_id' => $user->id,
            'name' => 'fgd',
            'price' => 12.00,
            'stock' => 21,
            'category' => 'Personal Care',
            'barcode' => 'BAR-101',
        ]);

        $this->assertDatabaseHas('products', [
            'user_id' => $user->id,
            'name' => 'fghfhg',
            'price' => 23.00,
            'stock' => 134,
            'category' => 'Drinks',
        ]);
    }

    public function test_sync_updates_existing_product_instead_of_duplicating(): void
    {
        $user = User::create([
            'username' => 'jiccastore_' . uniqid(),
            'full_name' => 'Jicca Dela Cruz',
            'password' => 'secret123',
            'role' => 'client',
            'is_active' => true,
        ]);

        $existing = Product::create([
            'user_id' => $user->id,
            'name' => 'Coke',
            'price' => 20.00,
            'stock' => 10,
            'category' => 'Drinks',
            'barcode' => 'BAR-COKE',
        ]);

        $payload = [
            'products' => [
                [
                    'client_id' => 999,
                    'name' => 'Coke',
                    'price' => 25.00, // updated price
                    'stock' => 20,    // updated stock
                    'category' => 'Drinks',
                    'barcode' => 'BAR-COKE',
                ],
            ],
        ];

        $response = $this->actingAs($user, 'sanctum')->postJson('/api/sync/products', $payload);

        $response->assertStatus(200);

        // Assert no duplicate was created
        $this->assertEquals(1, Product::where('user_id', $user->id)->where('name', 'Coke')->count());

        $this->assertDatabaseHas('products', [
            'id' => $existing->id,
            'user_id' => $user->id,
            'price' => 25.00,
            'stock' => 20,
        ]);
    }
}
