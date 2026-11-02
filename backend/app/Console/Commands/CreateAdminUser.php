<?php

namespace App\Console\Commands;

use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Hash;

class CreateAdminUser extends Command
{
    /**
     * The name and signature of the console command.
     *
     * @var string
     */
    protected $signature = 'make:admin {username?} {--name=} {--password=} {--pin=} {--email=}';

    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'Create a new admin user or promote an existing user to admin';

    /**
     * Execute the console command.
     */
    public function handle()
    {
        $username = $this->argument('username') ?: $this->ask('Enter admin username', 'admin');
        $user = User::where('username', $username)->first();

        if ($user) {
            if ($this->confirm("User '{$username}' already exists. Promote this user to Admin?", true)) {
                $user->role = 'admin';
                $user->is_active = true;
                if ($this->option('password')) {
                    $user->password = Hash::make($this->option('password'));
                }
                if ($this->option('pin')) {
                    $user->pin = $this->option('pin');
                }
                $user->save();
                $this->info("User '{$username}' successfully promoted to Admin!");
                return 0;
            }
            return 1;
        }

        $fullName = $this->option('name') ?: $this->ask('Enter full name', 'System Administrator');
        $email = $this->option('email') ?: $this->ask('Enter email (optional)', null);
        $password = $this->option('password') ?: $this->secret('Enter password (min 4 characters)');
        $pin = $this->option('pin') ?: $this->ask('Enter PIN (optional, 4-6 digits)', '9999');

        if (empty($password)) {
            $password = 'admin123';
            $this->comment('Using default password: admin123');
        }

        $admin = User::create([
            'username' => $username,
            'full_name' => $fullName,
            'email' => $email,
            'password' => Hash::make($password),
            'pin' => !empty($pin) ? $pin : null,
            'role' => 'admin',
            'is_active' => true,
        ]);

        $this->info("Admin account '{$admin->username}' created successfully!");
        $this->table(
            ['Username', 'Full Name', 'Role', 'Status', 'PIN Set'],
            [[$admin->username, $admin->full_name, $admin->role, $admin->is_active ? 'Active' : 'Inactive', !empty($admin->pin) ? 'Yes' : 'No']]
        );

        return 0;
    }
}

