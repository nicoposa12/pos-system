<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class StoreOrderNumberTest extends TestCase
{
    use RefreshDatabase;

    private function createStore(string $suffix): array
    {
        $user = User::create([
            'username' => 'store_' . $suffix . '_' . uniqid(),
            'full_name' => 'Store ' . $suffix,
            'password' => 'secret123',
            'role' => 'client',
            'is_active' => true,
        ]);

        $product = Product::create([
            'user_id' => $user->id,
            'name' => 'Item ' . $suffix,
            'price' => 50.00,
            'stock' => 100.000,
            'unit' => 'pcs',
        ]);

        return [$user, $product];
    }

    private function checkout(User $user, Product $product)
    {
        return $this->actingAs($user, 'sanctum')->postJson('/api/transactions', [
            'total_amount' => 50.00,
            'payment_method' => 'cash',
            'cash_received' => 50.00,
            'change_amount' => 0.0,
            'items' => [
                [
                    'product_id' => $product->id,
                    'quantity' => 1,
                    'subtotal' => 50.00,
                ],
            ],
        ]);
    }

    public function test_each_store_continues_sequentially_from_its_last_order_number_and_new_stores_start_at_one(): void
    {
        [$store1, $product1] = $this->createStore('one');
        [$store2, $product2] = $this->createStore('two');
        [$store3, $product3] = $this->createStore('three');

        // Simulate existing backfilled history before per-store numbering:
        // Store 2's last order was #89; Store 1's last order was #90.
        $now = now()->toDateTimeString();
        DB::table('transactions')->insert([
            [
                'id' => 89,
                'user_id' => $store2->id,
                'order_number' => 89,
                'total_amount' => 50.00,
                'discount' => 0.00,
                'cash_received' => 50.00,
                'change_amount' => 0.00,
                'payment_method' => 'cash',
                'date' => $now,
                'created_at' => $now,
                'updated_at' => $now,
            ],
            [
                'id' => 90,
                'user_id' => $store1->id,
                'order_number' => 90,
                'total_amount' => 50.00,
                'discount' => 0.00,
                'cash_received' => 50.00,
                'change_amount' => 0.00,
                'payment_method' => 'cash',
                'date' => $now,
                'created_at' => $now,
                'updated_at' => $now,
            ],
        ]);

        // Store 2 checks out next -> continues from 89 -> 90 (even though DB id is 91)
        $s2Next = $this->checkout($store2, $product2);
        $s2Next->assertStatus(201);
        $this->assertSame(90, $s2Next->json('transaction.order_number'));

        // Store 1 checks out next -> continues from 90 -> 91 (even though Store 2 just sold)
        $s1Next = $this->checkout($store1, $product1);
        $s1Next->assertStatus(201);
        $this->assertSame(91, $s1Next->json('transaction.order_number'));

        // Subsequent sales continue sequentially per store without cross-store gaps
        $s2Second = $this->checkout($store2, $product2);
        $s2Second->assertStatus(201);
        $this->assertSame(91, $s2Second->json('transaction.order_number'));

        $s1Second = $this->checkout($store1, $product1);
        $s1Second->assertStatus(201);
        $this->assertSame(92, $s1Second->json('transaction.order_number'));

        // Brand-new Store 3 with no prior orders starts at #1 -> #2
        $s3First = $this->checkout($store3, $product3);
        $s3First->assertStatus(201);
        $this->assertSame(1, $s3First->json('transaction.order_number'));

        $s3Second = $this->checkout($store3, $product3);
        $s3Second->assertStatus(201);
        $this->assertSame(2, $s3Second->json('transaction.order_number'));
    }

    public function test_by_order_lookup_is_strictly_scoped_to_authenticated_store(): void
    {
        [$store1, $product1] = $this->createStore('lookup_one');
        [$store2, $product2] = $this->createStore('lookup_two');

        $s1Order1 = $this->checkout($store1, $product1)->assertStatus(201);
        $s2Order1 = $this->checkout($store2, $product2)->assertStatus(201);

        $this->assertSame(1, $s1Order1->json('transaction.order_number'));
        $this->assertSame(1, $s2Order1->json('transaction.order_number'));
        $this->assertNotSame($s1Order1->json('transaction.id'), $s2Order1->json('transaction.id'));

        $lookup1 = $this->actingAs($store1, 'sanctum')->getJson('/api/transactions/by-order/1');
        $lookup1->assertStatus(200);
        $this->assertSame($s1Order1->json('transaction.id'), $lookup1->json('transaction.id'));

        $lookup2 = $this->actingAs($store2, 'sanctum')->getJson('/api/transactions/by-order/1');
        $lookup2->assertStatus(200);
        $this->assertSame($s2Order1->json('transaction.id'), $lookup2->json('transaction.id'));

        $this->actingAs($store1, 'sanctum')
            ->getJson('/api/transactions/by-order/999')
            ->assertStatus(404);
    }

    public function test_offline_batch_sync_assigns_sequential_store_order_numbers(): void
    {
        [$store1, $product1] = $this->createStore('sync_one');
        [$store2, $product2] = $this->createStore('sync_two');

        // Store 2 creates a sale first so global id advances
        $this->checkout($store2, $product2)->assertStatus(201);

        $syncRes = $this->actingAs($store1, 'sanctum')->postJson('/api/sync', [
            'transactions' => [
                [
                    'client_id' => 10,
                    'total_amount' => 50.0,
                    'payment_method' => 'cash',
                    'date' => now()->toIso8601String(),
                    'items' => [
                        ['product_id' => $product1->id, 'quantity' => 1, 'subtotal' => 50.0],
                    ],
                ],
                [
                    'client_id' => 11,
                    'total_amount' => 50.0,
                    'payment_method' => 'cash',
                    'date' => now()->toIso8601String(),
                    'items' => [
                        ['product_id' => $product1->id, 'quantity' => 1, 'subtotal' => 50.0],
                    ],
                ],
            ],
        ]);

        $syncRes->assertStatus(200);
        $this->assertSame(1, $syncRes->json('synced.0.order_number'));
        $this->assertSame(2, $syncRes->json('synced.1.order_number'));
    }
}
