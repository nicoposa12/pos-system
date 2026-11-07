<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class AdminClientManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_non_admin_cannot_access_admin_routes()
    {
        $client = User::create([
            'username' => 'test_cashier_' . uniqid(),
            'full_name' => 'Test Cashier',
            'password' => 'secret123',
            'role' => 'client',
            'is_active' => true,
        ]);

        $response = $this->actingAs($client, 'sanctum')->getJson('/api/admin/clients');
        $response->assertStatus(403);
    }

    public function test_admin_can_access_admin_routes_and_list_clients()
    {
        $admin = User::create([
            'username' => 'test_admin_' . uniqid(),
            'full_name' => 'Admin Boss',
            'password' => 'secret123',
            'role' => 'admin',
            'is_active' => true,
        ]);

        $response = $this->actingAs($admin, 'sanctum')->getJson('/api/admin/clients');
        $response->assertStatus(200)
            ->assertJsonStructure([
                'summary' => [
                    'total_users',
                    'total_clients',
                    'active_clients',
                    'inactive_clients',
                    'total_network_sales',
                ],
                'clients',
            ]);
    }

    public function test_admin_can_create_new_client_and_toggle_status()
    {
        $admin = User::create([
            'username' => 'test_admin_2_' . uniqid(),
            'full_name' => 'Admin Boss 2',
            'password' => 'secret123',
            'role' => 'admin',
            'is_active' => true,
        ]);

        $newUsername = 'new_store_' . uniqid();
        $createRes = $this->actingAs($admin, 'sanctum')->postJson('/api/admin/clients', [
            'username' => $newUsername,
            'full_name' => 'New Store Owner',
            'password' => 'pass1234',
            'pin' => '1234',
            'role' => 'client',
        ]);

        $createRes->assertStatus(201);
        $clientId = $createRes->json('user.id');

        // Toggle status to deactivated
        $toggleRes = $this->actingAs($admin, 'sanctum')->patchJson("/api/admin/clients/{$clientId}/toggle-status");
        $toggleRes->assertStatus(200)
            ->assertJson(['is_active' => false]);

        // Attempt login as deactivated user should fail
        $loginRes = $this->postJson('/api/auth/login', [
            'username' => $newUsername,
            'password' => 'pass1234',
        ]);
        $loginRes->assertStatus(422);
    }

    public function test_public_registration_is_blocked()
    {
        $response = $this->postJson('/api/auth/register', [
            'username' => 'self_registered',
            'full_name' => 'Self Registered',
            'password' => 'password123',
        ]);

        $response->assertStatus(403);
    }

    public function test_pin_login_is_strictly_device_scoped()
    {
        // Store A and Store B both use PIN 5678
        User::create([
            'username' => 'store_a',
            'full_name' => 'Store A',
            'password' => 'pass123',
            'pin' => '5678',
            'role' => 'client',
            'is_active' => true,
        ]);

        User::create([
            'username' => 'store_b',
            'full_name' => 'Store B',
            'password' => 'pass123',
            'pin' => '5678',
            'role' => 'client',
            'is_active' => true,
        ]);

        User::create([
            'username' => 'admin_test',
            'full_name' => 'Admin Test',
            'password' => 'pass123',
            'pin' => '9999',
            'role' => 'admin',
            'is_active' => true,
        ]);

        // Device A (scoped to store_a) using PIN 5678 must log into Store A
        $resA = $this->postJson('/api/auth/pin-login', [
            'pin' => '5678',
            'username' => 'store_a',
        ]);
        $resA->assertStatus(200);
        $this->assertEquals('store_a', $resA->json('user.username'));

        // Device B (scoped to store_b) using PIN 5678 must log into Store B, NOT Store A
        $resB = $this->postJson('/api/auth/pin-login', [
            'pin' => '5678',
            'username' => 'store_b',
        ]);
        $resB->assertStatus(200);
        $this->assertEquals('store_b', $resB->json('user.username'));

        // If Device A enters a random PIN (e.g. 9991), it fails
        $resFail = $this->postJson('/api/auth/pin-login', [
            'pin' => '9991',
            'username' => 'store_a',
        ]);
        $resFail->assertStatus(401);

        // Strict Terminal Isolation: Device A entering Admin PIN (9999) must fail
        $resAdminOnDeviceA = $this->postJson('/api/auth/pin-login', [
            'pin' => '9999',
            'username' => 'store_a',
        ]);
        $resAdminOnDeviceA->assertStatus(401);

        // Admin device using Admin PIN logs in successfully
        $resAdmin = $this->postJson('/api/auth/pin-login', [
            'pin' => '9999',
            'username' => 'admin_test',
        ]);
        $resAdmin->assertStatus(200);
        $this->assertEquals('admin_test', $resAdmin->json('user.username'));

        // An unscoped client PIN request fails
        $resUnscoped = $this->postJson('/api/auth/pin-login', [
            'pin' => '5678',
        ]);
        $resUnscoped->assertStatus(401);
    }

    public function test_admin_can_provision_store_with_photo_and_update_it()
    {
        Storage::fake('public');

        $admin = User::create([
            'username' => 'photo_admin_' . uniqid(),
            'full_name' => 'Photo Admin',
            'password' => 'secret123',
            'role' => 'admin',
            'is_active' => true,
        ]);

        $photoFile = UploadedFile::fake()->image('store_front.jpg', 400, 400);

        // 1. Provision store with photo
        $createRes = $this->actingAs($admin, 'sanctum')->post('/api/admin/clients', [
            'username' => 'photo_store_' . uniqid(),
            'full_name' => 'Bakery Store',
            'password' => 'pass1234',
            'role' => 'client',
            'image' => $photoFile,
        ], ['Accept' => 'application/json']);

        $createRes->assertStatus(201);
        $this->assertNotNull($createRes->json('user.image_path'));
        $this->assertStringContainsString('/api/media/stores/', $createRes->json('user.image_path'));
        $clientId = $createRes->json('user.id');

        // 2. Fetch clients list and verify image_path is included
        $listRes = $this->actingAs($admin, 'sanctum')->getJson('/api/admin/clients');
        $listRes->assertStatus(200);
        $clientInList = collect($listRes->json('clients'))->firstWhere('id', $clientId);
        $this->assertNotNull($clientInList['image_path']);

        // 3. Update store photo
        $newPhotoFile = UploadedFile::fake()->image('new_store.png', 400, 400);
        $updateRes = $this->actingAs($admin, 'sanctum')->post("/api/admin/clients/{$clientId}?_method=PUT", [
            'full_name' => 'Bakery Deluxe',
            'image' => $newPhotoFile,
        ], ['Accept' => 'application/json']);

        $updateRes->assertStatus(200);
        $this->assertNotNull($updateRes->json('user.image_path'));

        // 4. Remove store photo
        $removeRes = $this->actingAs($admin, 'sanctum')->post("/api/admin/clients/{$clientId}?_method=PUT", [
            'remove_image' => 1,
        ], ['Accept' => 'application/json']);

        $removeRes->assertStatus(200);
        $this->assertNull($removeRes->json('user.image_path'));
    }
}
