<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Transaction extends Model
{
    use HasFactory;

    protected $fillable = [
        'user_id',
        'total_amount',
        'discount',
        'cash_received',
        'change_amount',
        'payment_method',
        'date',
    ];

    protected $casts = [
        'total_amount' => 'float',
        'discount' => 'float',
        'cash_received' => 'float',
        'change_amount' => 'float',
        'date' => 'datetime',
    ];

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
