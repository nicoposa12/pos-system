<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ReturnDecimalQuantityTest extends TestCase
{
    use RefreshDatabase;

    public function test_decimal_sale_and_exact_decimal_return_restore_stock_and_zero_total(): void
    {
        $user = User::create([
            'username' => 'store_' . uniqid(),
            'full_name' => 'Store Owner',
            'password' => 'secret123',
            'role' => 'client',
            'is_active' => true,
        ]);

        $product = Product::create([
            'user_id' => $user->id,
            'name' => '1231',
            'price' => 123.00,
            'stock' => 10.000,
            'unit' => 'kg',
        ]);

        // Sell 0.5 units @ 123.00 = 61.50
        $saleRes = $this->actingAs($user, 'sanctum')->postJson('/api/transactions', [
            'total_amount' => 61.50,
            'payment_method' => 'cash',
            'cash_received' => 61.50,
            'change_amount' => 0.0,
            'items' => [
                [
                    'product_id' => $product->id,
                    'quantity' => 0.5,
                    'subtotal' => 61.50,
                ],
            ],
        ]);

        $saleRes->assertStatus(201);
        $txId = $saleRes->json('transaction.id');

        $product->refresh();
        $this->assertEqualsWithDelta(9.5, (float) $product->stock, 0.0001);

        // Return 0.5 units -> should restore full 0.5 stock and set transaction total to 0.00
        $retRes = $this->actingAs($user, 'sanctum')->postJson("/api/transactions/{$txId}/returns", [
            'product_id' => $product->id,
            'quantity' => 0.5,
            'reason' => 'Damaged',
        ]);

        $retRes->assertStatus(201);
        $this->assertEqualsWithDelta(10.0, (float) $retRes->json('product_stock'), 0.0001);
        $this->assertEqualsWithDelta(0.0, (float) $retRes->json('transaction.total_amount'), 0.01);
        $this->assertEqualsWithDelta(0.5, (float) $retRes->json('transaction.returns.0.quantity'), 0.0001);

        // Attempting to return more should be rejected
        $overRes = $this->actingAs($user, 'sanctum')->postJson("/api/transactions/{$txId}/returns", [
            'product_id' => $product->id,
            'quantity' => 0.1,
            'reason' => 'Extra',
        ]);
        $overRes->assertStatus(422);
    }
}
