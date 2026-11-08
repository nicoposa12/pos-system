import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindako/models/product.dart';

void main() {
  group('Online Product Model Tests', () {
    test('Product.fromJson parses cloud API JSON response correctly', () {
      final json = {
        'id': 101,
        'user_id': 4,
        'name': 'Coke',
        'category': 'Drinks',
        'price': 25.0,
        'stock': 20,
        'barcode': '123456',
        'image_path': 'https://api.test/media/products/coke.png',
        'variants': jsonEncode([
          {'name': '1.5L', 'price': 75.0, 'stock': 10},
        ]),
        'created_at': DateTime.now().toIso8601String(),
      };

      final p = Product.fromJson(json);
      expect(p.id, equals(101));
      expect(p.name, equals('Coke'));
      expect(p.price, equals(25.0));
      expect(p.stock, equals(20));
      expect(p.variants.length, equals(1));
      expect(p.variants.first.name, equals('1.5L'));
      expect(p.variants.first.price, equals(75.0));
    });

    test('Product.variantsPayload serializes variants for cloud API requests', () {
      final productWithVariants = Product(
        id: 15,
        userId: 4,
        name: 'Milk Tea',
        price: 85.0,
        stock: 30,
        category: 'Drinks',
        variants: [
          ProductVariant(name: 'Large', price: 95.0, stock: 15),
          ProductVariant(name: 'Medium', price: 85.0, stock: 15),
        ],
        createdAt: DateTime.now(),
      );

      final payload = productWithVariants.variantsPayload;
      expect(payload, isNotNull);
      final decoded = jsonDecode(payload!) as List;
      expect(decoded.length, equals(2));
      expect(decoded[0]['name'], equals('Large'));
      expect(decoded[1]['price'], equals(85.0));

      final productWithoutVariants = Product(
        id: 16,
        userId: 4,
        name: 'Mineral Water',
        price: 20.0,
        stock: 50,
        createdAt: DateTime.now(),
      );
      expect(productWithoutVariants.variantsPayload, isNull);
    });

    test('Product.copyWith updates fields while preserving existing values', () {
      final p = Product(
        name: 'Test Product',
        price: 50.0,
        stock: 10,
        userId: 4,
        createdAt: DateTime.now(),
      );

      final updated = p.copyWith(id: 77, stock: 15);
      expect(updated.id, equals(77));
      expect(updated.stock, equals(15));
      expect(updated.name, equals('Test Product'));
    });
  });
}
