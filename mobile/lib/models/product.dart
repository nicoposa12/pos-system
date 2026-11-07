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
  final bool isSynced;
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
    this.isSynced = false,
    required this.createdAt,
  });

  bool get hasValidImage => imagePath != null && imagePath!.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'category': category,
      'price': price,
      'stock': stock,
      'barcode': barcode,
      'image_path': imagePath,
      'variants': jsonEncode(variants.map((v) => v.toMap()).toList()),
      'is_synced': isSynced ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(map['created_at']);
    } catch (_) {
      parsedDate = DateTime.now();
    }

    List<ProductVariant> parsedVariants = [];
    if (map['variants'] != null && map['variants'] is String) {
      try {
        final List<dynamic> list = jsonDecode(map['variants']);
        parsedVariants = list.map((v) => ProductVariant.fromMap(v)).toList();
      } catch (_) {}
    }

    return Product(
      id: map['id'],
      userId: map['user_id'] ?? 0,
      name: map['name'],
      category: map['category'],
      price: map['price'],
      stock: map['stock'],
      barcode: map['barcode'],
      imagePath: map['image_path'],
      variants: parsedVariants,
      isSynced: (map['is_synced'] == 1 || map['is_synced'] == true),
      createdAt: parsedDate,
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
    bool? isSynced,
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
      isSynced: isSynced ?? this.isSynced,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
