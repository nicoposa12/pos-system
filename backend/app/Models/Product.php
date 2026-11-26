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
        'cost_price',
        'stock',
        'unit',
        'barcode',
        'image_path',
        'variants',
    ];

    protected $casts = [
        'price' => 'float',
        'cost_price' => 'float',
        'stock' => 'float',
        'variants' => 'array',
    ];

    /**
     * Resolves the original/cost price to snapshot for a sale item.
     *
     * Prefers an exact variant match (by name, then by selling price within 5 cents)
     * when that variant specifies its own `cost_price` / `costPrice`, falling back
     * to the product's base `cost_price`.
     */
    public function resolveUnitCostForSellingPrice(float $unitSellingPrice, ?string $variantName = null): ?float
    {
        $variants = $this->variants;
        if (is_array($variants) && !empty($variants)) {
            $trimmedName = $variantName !== null ? strtolower(trim($variantName)) : '';

            if ($trimmedName !== '') {
                foreach ($variants as $variant) {
                    if (!is_array($variant)) {
                        continue;
                    }
                    $vName = strtolower(trim((string) ($variant['name'] ?? '')));
                    if ($vName === $trimmedName) {
                        $variantCost = $this->extractNumericCost($variant);
                        if ($variantCost !== null) {
                            return $variantCost;
                        }
                        break;
                    }
                }
            }

            foreach ($variants as $variant) {
                if (!is_array($variant) || !isset($variant['price'])) {
                    continue;
                }
                if (abs((float) $variant['price'] - $unitSellingPrice) < 0.05) {
                    $variantCost = $this->extractNumericCost($variant);
                    if ($variantCost !== null) {
                        return $variantCost;
                    }
                }
            }
        }

        return $this->cost_price !== null ? round((float) $this->cost_price, 2) : null;
    }

    private function extractNumericCost(array $variant): ?float
    {
        $raw = $variant['cost_price'] ?? $variant['costPrice'] ?? null;
        if ($raw === null || $raw === '' || !is_numeric($raw)) {
            return null;
        }
        $value = (float) $raw;

        return $value >= 0 ? round($value, 2) : null;
    }

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
