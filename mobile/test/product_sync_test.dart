import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindako/models/product.dart';

void main() {
  group('Product Sync Model & Payload Tests', () {
    test('Product model defaults isSynced to false for offline creations', () {
      final p = Product(
        name: 'fgd',
        price: 12.0,
        stock: 21,
        userId: 4,
        category: 'Personal Care',
        createdAt: DateTime.now(),
      );

      expect(p.isSynced, isFalse);
      final map = p.toMap();
      expect(map['is_synced'], equals(0));
    });

    test('Product model serializes and deserializes isSynced accurately', () {
      final mapSynced = {
        'id': 101,
        'user_id': 4,
        'name': 'Coke',
        'category': 'Drinks',
        'price': 25.0,
        'stock': 20,
        'barcode': '123456',
        'image_path': '/path/to/coke.png',
        'variants': '[]',
        'is_synced': 1,
        'created_at': DateTime.now().toIso8601String(),
      };

      final pSynced = Product.fromMap(mapSynced);
      expect(pSynced.isSynced, isTrue);

      final mapUnsynced = Map<String, dynamic>.from(mapSynced);
      mapUnsynced['is_synced'] = 0;
      final pUnsynced = Product.fromMap(mapUnsynced);
      expect(pUnsynced.isSynced, isFalse);
    });

    test('Product.copyWith supports updating isSynced flag', () {
      final p = Product(
        name: 'Test Product',
        price: 50.0,
        stock: 10,
        userId: 4,
        isSynced: false,
        createdAt: DateTime.now(),
      );

      final syncedP = p.copyWith(id: 77, isSynced: true);
      expect(syncedP.id, equals(77));
      expect(syncedP.isSynced, isTrue);
      expect(syncedP.name, equals('Test Product'));
    });

    test('Offline batch sync payload encodes variants and product fields properly', () {
      final productWithVariants = Product(
        id: 15,
        userId: 4,
        name: 'Milk Tea',
        price: 85.0,
        stock: 30,
        category: 'Drinks',
        isSynced: false,
        variants: [
          ProductVariant(name: 'Large', price: 95.0, stock: 15),
          ProductVariant(name: 'Medium', price: 85.0, stock: 15),
        ],
        createdAt: DateTime.now(),
      );

      final payload = {
        'client_id': productWithVariants.id,
        'name': productWithVariants.name,
        'price': productWithVariants.price,
        'stock': productWithVariants.stock,
        'category': productWithVariants.category,
        'barcode': productWithVariants.barcode,
        'variants': productWithVariants.variants.isNotEmpty
            ? jsonEncode(productWithVariants.variants.map((v) => v.toMap()).toList())
            : null,
      };

      expect(payload['client_id'], equals(15));
      expect(payload['name'], equals('Milk Tea'));
      expect(payload['price'], equals(85.0));
      expect(payload['variants'], isNotNull);
      final decodedVariants = jsonDecode(payload['variants'] as String) as List;
      expect(decodedVariants.length, equals(2));
      expect(decodedVariants[0]['name'], equals('Large'));
    });
  });
}
