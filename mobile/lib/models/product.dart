import 'dart:convert';

/// Universal quantity formatting utility:
/// - Whole numbers: 20 -> "20"
/// - Decimals: 20.5 -> "20.5", 0.75 -> "0.75", 1.250 -> "1.25"
String formatQuantity(num q) {
  if (q % 1 == 0) return q.toInt().toString();
  return q.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '');
}

class ProductVariant {
  final String name;
  final double price;
  final double? costPrice;
  final double? stock;
  final String? imagePath;

  ProductVariant({
    required this.name,
    required this.price,
    this.costPrice,
    this.stock,
    this.imagePath,
  });

  bool get hasValidImage => imagePath != null && imagePath!.isNotEmpty;
  bool get hasCostPrice => costPrice != null;
  double? get unitProfit => costPrice != null ? price - costPrice! : null;
  double? get profitMarginPercent =>
      (costPrice != null && price > 0) ? ((price - costPrice!) / price) * 100 : null;

  Map<String, dynamic> toMap() => {
    'name': name,
    'price': price,
    'cost_price': ?costPrice,
    'stock': stock,
    'imagePath': imagePath,
  };

  factory ProductVariant.fromMap(Map<String, dynamic> map) {
    final rawCost = map['cost_price'] ?? map['costPrice'];
    return ProductVariant(
      name: map['name'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ??
          double.tryParse(map['price']?.toString() ?? '') ??
          0.0,
      costPrice: rawCost is num
          ? rawCost.toDouble()
          : double.tryParse(rawCost?.toString() ?? ''),
      stock: (map['stock'] ?? map['quantity']) != null
          ? ((map['stock'] ?? map['quantity']) as num).toDouble()
          : null,
      imagePath: map['imagePath'] as String?,
    );
  }
}

class Product {
  final int? id;
  final int userId;
  final String name;
  final String? category;
  final double price;
  final double? costPrice;
  final double stock;
  final String unit;
  final String? barcode;
  final String? imagePath;
  final List<ProductVariant> variants;
  final DateTime createdAt;

  Product({
    this.id,
    required this.userId,
    required this.name,
    this.category,
    required this.price,
    this.costPrice,
    required this.stock,
    this.unit = 'pcs',
    this.barcode,
    this.imagePath,
    this.variants = const [],
    required this.createdAt,
  });

  bool get hasValidImage => imagePath != null && imagePath!.isNotEmpty;

  bool get hasCostPrice => costPrice != null;

  /// Profit per single unit (`selling price - original/cost price`), or `null` if cost price is unset.
  double? get unitProfit => costPrice != null ? price - costPrice! : null;

  /// Gross margin percentage `((price - costPrice) / price) * 100`, or `null` if cost is unset or price is 0.
  double? get profitMarginPercent =>
      (costPrice != null && price > 0) ? ((price - costPrice!) / price) * 100 : null;

  /// Total original capital currently sitting in stock (`costPrice * stock`).
  double? get stockCostValue => costPrice != null ? costPrice! * stock : null;

  /// Total retail value currently sitting in stock (`price * stock`).
  double get stockRetailValue => price * stock;

  /// Expected gross profit if all current stock sells at [price].
  double? get potentialStockProfit => unitProfit != null ? unitProfit! * stock : null;

  /// Returns whether this product's unit supports fractional/decimal quantities
  bool get allowsDecimal => ['kg', 'g', 'gram', 'grams', 'kilo', 'kilos', 'liter', 'liters', 'l', 'meter', 'meters', 'm'].contains(unit.trim().toLowerCase());

  String get formattedStock => '${formatQuantity(stock)} ${unit.trim().isNotEmpty ? unit.trim() : 'pcs'}';

  /// JSON-encoded variants for API create/update requests, or `null` when empty.
  String? get variantsPayload => variants.isNotEmpty
      ? jsonEncode(variants.map((v) => v.toMap()).toList())
      : null;

  /// Builds a product from the API payload (`/products`).
  factory Product.fromJson(Map<String, dynamic> json) {
    final rawVariants = json['variants'];
    List<dynamic> variantList = const [];
    if (rawVariants is List) {
      variantList = rawVariants;
    } else if (rawVariants is String && rawVariants.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawVariants);
        if (decoded is List) variantList = decoded;
      } catch (_) {}
    }

    final image = json['image_path']?.toString().trim();
    final rawCost = json['cost_price'];

    return Product(
      id: (json['id'] as num?)?.toInt(),
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString(),
      price: (json['price'] as num?)?.toDouble() ??
          double.tryParse(json['price']?.toString() ?? '') ??
          0.0,
      costPrice: rawCost is num
          ? rawCost.toDouble()
          : double.tryParse(rawCost?.toString() ?? ''),
      stock: (json['stock'] as num?)?.toDouble() ?? 0.0,
      unit: json['unit']?.toString().trim() ?? 'pcs',
      barcode: json['barcode']?.toString(),
      imagePath: (image != null && image.isNotEmpty) ? image : null,
      variants: variantList
          .whereType<Map>()
          .map((v) => ProductVariant.fromMap(Map<String, dynamic>.from(v)))
          .toList(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Product copyWith({
    int? id,
    int? userId,
    String? name,
    String? category,
    double? price,
    double? costPrice,
    bool clearCostPrice = false,
    double? stock,
    String? unit,
    String? barcode,
    String? imagePath,
    List<ProductVariant>? variants,
    DateTime? createdAt,
  }) {
    return Product(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      category: category ?? this.category,
      price: price ?? this.price,
      costPrice: clearCostPrice ? null : (costPrice ?? this.costPrice),
      stock: stock ?? this.stock,
      unit: unit ?? this.unit,
      barcode: barcode ?? this.barcode,
      imagePath: imagePath ?? this.imagePath,
      variants: variants ?? this.variants,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
