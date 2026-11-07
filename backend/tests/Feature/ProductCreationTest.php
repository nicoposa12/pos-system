<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Tests\TestCase;

class ProductCreationTest extends TestCase
{
    use RefreshDatabase;

    public function test_can_create_product_via_json(): void
    {
        $user = User::create([
            'username' => 'testuser_' . uniqid(),
            'full_name' => 'Test User',
            'password' => 'secret123',
            'role' => 'client',
            'is_active' => true,
        ]);

        $response = $this->actingAs($user, 'sanctum')->postJson('/api/products', [
            'name' => 'San Miguel Beer',
            'price' => 55.0,
            'stock' => 24,
            'category' => 'Drinks',
            'barcode' => 'SMB123',
        ]);

        $response->assertStatus(201)
            ->assertJsonStructure([
                'message',
                'product' => ['id', 'name', 'price', 'stock', 'category', 'barcode'],
            ]);
    }

    public function test_can_create_product_via_multipart_with_image(): void
    {
        $user = User::create([
            'username' => 'testuser_' . uniqid(),
            'full_name' => 'Test User',
            'password' => 'secret123',
            'role' => 'client',
            'is_active' => true,
        ]);

        $file = UploadedFile::fake()->image('product.jpg');

        $response = $this->actingAs($user, 'sanctum')->post('/api/products', [
            'name' => 'Red Horse',
            'price' => 60.0,
            'stock' => 12,
            'category' => 'Drinks',
            'image' => $file,
        ]);

        $response->assertStatus(201);
    }
}

