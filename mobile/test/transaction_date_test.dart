import 'package:flutter_test/flutter_test.dart';
import 'package:tindako/models/transaction.dart';

void main() {
  group('SaleTransaction date & realtime timezone tests', () {
    test('uses created_at as authoritative UTC timestamp and converts to local', () {
      // Simulating Order #28: created at 10:21 PM Philippine Time (14:21 UTC on Nov 9, 2026)
      final json = {
        'id': 28,
        'user_id': 1,
        'total_amount': 246.0,
        'payment_method': 'cash',
        'date': '2026-11-09T22:21:00.000000Z', // Buggy date was shifted +8h
        'created_at': '2026-11-09T14:21:00.000000Z', // Real server UTC time
      };

      final tx = SaleTransaction.fromJson(json);

      // Verify it parsed created_at
      expect(tx.id, 28);
      expect(tx.date.isUtc, isFalse); // toLocal converts to local time

      // Verify that tx.date equals the local representation of 14:21:00 UTC
      final expectedLocal = DateTime.parse('2026-11-09T14:21:00.000000Z').toLocal();
      expect(tx.date.year, expectedLocal.year);
      expect(tx.date.month, expectedLocal.month);
      expect(tx.date.day, expectedLocal.day);
      expect(tx.date.hour, expectedLocal.hour);
      expect(tx.date.minute, expectedLocal.minute);
    });

    test('falls back to date when created_at is absent', () {
      final json = {
        'id': 29,
        'user_id': 1,
        'total_amount': 150.0,
        'payment_method': 'cash',
        'date': '2026-11-09T15:00:00.000000Z',
      };

      final tx = SaleTransaction.fromJson(json);
      final expectedLocal = DateTime.parse('2026-11-09T15:00:00.000000Z').toLocal();
      expect(tx.date, expectedLocal);
    });

    test('accurately calculates net quantities, subtotals, and total when items are returned', () {
      // Order #35 from screenshot:
      // Item 1: 8x product 10 (₱984.00 subtotal, unit price ₱123.00)
      // Item 2: 1x product 20 (₱123.00 subtotal, unit price ₱123.00)
      // Total: ₱1107.00
      // Customer returns 8 pcs of product 10
      final json = {
        'id': 35,
        'user_id': 1,
        'total_amount': 1107.0,
        'payment_method': 'pending',
        'customer_name': 'gy',
        'items': [
          {
            'product_id': 10,
            'quantity': 8,
            'subtotal': 984.0,
            'product': {'id': 10, 'name': '123'},
          },
          {
            'product_id': 20,
            'quantity': 1,
            'subtotal': 123.0,
            'product': {'id': 20, 'name': '12312'},
          },
        ],
        'returns': [
          {
            'product_id': 10,
            'quantity': 8,
          },
        ],
      };

      final tx = SaleTransaction.fromJson(json);

      expect(tx.id, 35);
      // Order total accurately reduced by ₱984.00 (1107 - 984 = 123)
      expect(tx.totalAmount, 123.0);

      // Item 1: fully returned
      final item1 = tx.items.firstWhere((i) => i['product_id'] == 10);
      expect(item1['quantity'], 0);
      expect(item1['original_quantity'], 8);
      expect(item1['returned_quantity'], 8);
      expect(item1['subtotal'], 0.0);
      expect(item1['unit_price'], 123.0);

      // Item 2: not returned
      final item2 = tx.items.firstWhere((i) => i['product_id'] == 20);
      expect(item2['quantity'], 1);
      expect(item2['original_quantity'], 1);
      expect(item2['returned_quantity'], 0);
      expect(item2['subtotal'], 123.0);
    });

    test('accurately calculates partial returns (e.g. 2 out of 8 returned)', () {
      final json = {
        'id': 35,
        'user_id': 1,
        'total_amount': 1107.0,
        'payment_method': 'pending',
        'customer_name': 'gy',
        'items': [
          {
            'product_id': 10,
            'quantity': 8,
            'subtotal': 984.0,
            'product': {'id': 10, 'name': '123'},
          },
          {
            'product_id': 20,
            'quantity': 1,
            'subtotal': 123.0,
            'product': {'id': 20, 'name': '12312'},
          },
        ],
        'returns': [
          {
            'product_id': 10,
            'quantity': 2,
          },
        ],
      };

      final tx = SaleTransaction.fromJson(json);

      // 6 remaining * 123 = 738. Item 2 = 123. Total = 861.0
      expect(tx.totalAmount, 861.0);

      final item1 = tx.items.firstWhere((i) => i['product_id'] == 10);
      expect(item1['quantity'], 6);
      expect(item1['original_quantity'], 8);
      expect(item1['returned_quantity'], 2);
      expect(item1['subtotal'], 738.0);
      expect(item1['unit_price'], 123.0);
    });
  });
}
