<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The original `pin` column was VARCHAR(10), sized for a plaintext 4–6 digit PIN.
 * PINs are now stored as bcrypt hashes (60 chars). PostgreSQL (Neon) strictly
 * enforces VARCHAR length, so every hashed PIN write failed with
 * SQLSTATE[22001] "value too long for type character varying(10)" -> HTTP 500.
 * (SQLite ignores VARCHAR length, which is why local tests passed.)
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('pin', 255)->nullable()->change();
        });
    }

    public function down(): void
    {
        // Intentionally non-destructive: shrinking back to 10 chars would
        // truncate/fail on existing bcrypt hashes.
    }
};

