<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('transactions', function (Blueprint $table) {
            $table->index(['user_id', 'date'], 'idx_transactions_user_date');
            $table->index(['user_id', 'updated_at'], 'idx_transactions_user_updated');
        });

        Schema::table('products', function (Blueprint $table) {
            $table->index(['user_id', 'updated_at'], 'idx_products_user_updated');
            $table->index(['user_id', 'category'], 'idx_products_user_category');
            $table->index(['user_id', 'barcode'], 'idx_products_user_barcode');
        });

        Schema::table('debts', function (Blueprint $table) {
            $table->index(['user_id', 'status'], 'idx_debts_user_status');
            $table->index(['user_id', 'updated_at'], 'idx_debts_user_updated');
        });

        Schema::table('transaction_items', function (Blueprint $table) {
            $table->index(['transaction_id', 'product_id'], 'idx_tx_items_tx_prod');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('transactions', function (Blueprint $table) {
            $table->dropIndex('idx_transactions_user_date');
            $table->dropIndex('idx_transactions_user_updated');
        });

        Schema::table('products', function (Blueprint $table) {
            $table->dropIndex('idx_products_user_updated');
            $table->dropIndex('idx_products_user_category');
            $table->dropIndex('idx_products_user_barcode');
        });

        Schema::table('debts', function (Blueprint $table) {
            $table->dropIndex('idx_debts_user_status');
            $table->dropIndex('idx_debts_user_updated');
        });

        Schema::table('transaction_items', function (Blueprint $table) {
            $table->dropIndex('idx_tx_items_tx_prod');
        });
    }
};
