<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Adds a store-scoped `order_number` column to `transactions`.
 *
 * Existing rows preserve their current numeric identity (`order_number = id`)
 * so historical receipts and records remain unchanged, while all subsequent
 * orders per store continue sequentially from that store's last order number
 * (and new stores start at 1).
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('transactions', function (Blueprint $table) {
            if (!Schema::hasColumn('transactions', 'order_number')) {
                $table->unsignedBigInteger('order_number')->nullable()->after('user_id');
            }
        });

        DB::table('transactions')
            ->whereNull('order_number')
            ->update(['order_number' => DB::raw('id')]);

        Schema::table('transactions', function (Blueprint $table) {
            $table->unsignedBigInteger('order_number')->nullable(false)->change();
            $table->unique(['user_id', 'order_number'], 'uniq_transactions_user_order_number');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('transactions', function (Blueprint $table) {
            $table->dropUnique('uniq_transactions_user_order_number');
            if (Schema::hasColumn('transactions', 'order_number')) {
                $table->dropColumn('order_number');
            }
        });
    }
};
