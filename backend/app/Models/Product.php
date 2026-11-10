<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Product extends Model
{
    use HasFactory;

    protected $fillable = [
        'user_id',
        'name',
        'category',
        'price',
        'stock',
        'unit',
        'barcode',
        'image_path',
        'variants',
    ];

    protected $casts = [
        'price' => 'float',
        'stock' => 'float',
        'variants' => 'array',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    /**
     * Accessor: Ensure image_path always resolves through the API media proxy
     * if it points to blocked *.r2.dev, old storage links, or relative paths.
     */
    public function getImagePathAttribute($value)
    {
        if (!$value) {
            return null;
        }

        // If it's already an API media proxy URL, return as-is
        if (str_contains($value, '/api/media/')) {
            return $value;
        }

        // If it's an r2.dev or /storage/ URL, extract filename and route through proxy
        if (str_contains($value, '.r2.dev/') || str_contains($value, '/storage/products/')) {
            $filename = basename(parse_url($value, PHP_URL_PATH) ?? $value);
            return url('/api/media/products/' . $filename);
        }

        // If it's stored as a relative path like 'products/xxx.jpg'
        if (str_starts_with($value, 'products/')) {
            return url('/api/media/' . $value);
        }

        return $value;
    }

    public function transactionItems()
    {
        return $this->hasMany(TransactionItem::class);
    }
}
