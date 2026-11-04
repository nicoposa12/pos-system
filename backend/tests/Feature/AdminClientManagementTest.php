<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
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

        // An unscoped client PIN request fails
        $resUnscoped = $this->postJson('/api/auth/pin-login', [
            'pin' => '5678',
        ]);
        $resUnscoped->assertStatus(401);
    }
}
