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
}
