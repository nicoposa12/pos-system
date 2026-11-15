<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Transaction extends Model
{
    use HasFactory;

    protected $fillable = [
        'user_id',
        'order_number',
        'total_amount',
        'discount',
        'cash_received',
        'change_amount',
        'payment_method',
        'date',
    ];

    protected $casts = [
        'order_number' => 'integer',
        'total_amount' => 'float',
        'discount' => 'float',
        'cash_received' => 'float',
        'change_amount' => 'float',
        'date' => 'datetime',
    ];

    protected static function booted(): void
    {
        static::creating(function (Transaction $transaction): void {
            if ($transaction->order_number === null && $transaction->user_id !== null) {
                $transaction->order_number = static::nextOrderNumberForUser((int) $transaction->user_id);
            }
        });
    }

    /**
     * Computes the next sequential order number for a specific store (`user_id`).
     * Should be called inside a database transaction; locks the store's `users` row
     * so concurrent checkouts within the same store serialize without blocking
     * other stores.
     */
    public static function nextOrderNumberForUser(int $userId): int
    {
        User::where('id', $userId)->lockForUpdate()->first();

        $lastOrderNumber = (int) (static::where('user_id', $userId)->max('order_number') ?? 0);

        return $lastOrderNumber + 1;
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function items()
    {
        return $this->hasMany(TransactionItem::class);
    }

    public function debt()
    {
        return $this->hasOne(Debt::class);
    }

    public function returns()
    {
        return $this->hasMany(ProductReturn::class);
    }
}
