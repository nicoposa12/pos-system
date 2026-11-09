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
  });
}
