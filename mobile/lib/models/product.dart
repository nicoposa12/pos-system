import 'dart:convert';

class ProductVariant {
  final String name;
  final double price;
  final int? stock;
  final String? imagePath;

  ProductVariant({
    required this.name,
    required this.price,
    this.stock,
    this.imagePath,
  });

  bool get hasValidImage => imagePath != null && imagePath!.isNotEmpty;

  Map<String, dynamic> toMap() => {
    'name': name,
    'price': price,
    'stock': stock,
    'imagePath': imagePath,
  };

  factory ProductVariant.fromMap(Map<String, dynamic> map) => 
      ProductVariant(
        name: map['name'] as String? ?? '', 
        price: (map['price'] as num?)?.toDouble() ?? 0.0,
        stock: (map['stock'] ?? map['quantity']) != null
            ? ((map['stock'] ?? map['quantity']) as num).toInt()
            : null,
        imagePath: map['imagePath'] as String?,
      );
}

class Product {
  final int? id;
  final int userId;
  final String name;
  final String? category;
  final double price;
  final int stock;
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
    required this.stock,
    this.barcode,
    this.imagePath,
    this.variants = const [],
    required this.createdAt,
  });

  bool get hasValidImage => imagePath != null && imagePath!.isNotEmpty;

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

    return Product(
      id: (json['id'] as num?)?.toInt(),
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString(),
      price: (json['price'] as num?)?.toDouble() ??
          double.tryParse(json['price']?.toString() ?? '') ??
          0.0,
      stock: (json['stock'] as num?)?.toInt() ?? 0,
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
    int? stock,
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
      stock: stock ?? this.stock,
      barcode: barcode ?? this.barcode,
      imagePath: imagePath ?? this.imagePath,
      variants: variants ?? this.variants,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
