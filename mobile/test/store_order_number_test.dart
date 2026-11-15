import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindako/models/transaction.dart';
import 'package:tindako/providers/transaction_provider.dart';
import 'package:tindako/widgets/receipt_dialog.dart';

void main() {
  group('Store-scoped order_number behavior', () {
    test('SaleTransaction parses order_number and prefers it for displayOrderNumber', () {
      final scoped = SaleTransaction.fromJson({
        'id': 92,
        'order_number': 90,
        'user_id': 2,
        'total_amount': 150.0,
        'payment_method': 'cash',
        'date': '2026-11-15T04:00:00.000000Z',
      });

      expect(scoped.id, 92);
      expect(scoped.orderNumber, 90);
      expect(scoped.displayOrderNumber, 90);

      final legacy = SaleTransaction.fromJson({
        'id': 89,
        'user_id': 2,
        'total_amount': 75.0,
        'payment_method': 'cash',
        'date': '2026-11-15T03:00:00.000000Z',
      });

      expect(legacy.id, 89);
      expect(legacy.orderNumber, isNull);
      expect(legacy.displayOrderNumber, 89);
    });

    test('findTransactionByOrderNumber resolves by orderNumber before falling back to legacy id', () async {
      final provider = TransactionProvider();
      provider.addCompletedTransaction(
        SaleTransaction(
          id: 90,
          orderNumber: 88,
          userId: 2,
          totalAmount: 100.0,
          date: DateTime(2026, 11, 15, 10, 0),
        ),
      );
      provider.addCompletedTransaction(
        SaleTransaction(
          id: 92,
          orderNumber: 90,
          userId: 2,
          totalAmount: 200.0,
          date: DateTime(2026, 11, 15, 11, 0),
        ),
      );

      final matched = await provider.findTransactionByOrderNumber(90);
      expect(matched, isNotNull);
      expect(matched!.id, 92);
      expect(matched.orderNumber, 90);

      // Legacy in-memory record without orderNumber still resolves by id
      provider.addCompletedTransaction(
        SaleTransaction(
          id: 45,
          userId: 2,
          totalAmount: 50.0,
          date: DateTime(2026, 11, 14, 9, 0),
        ),
      );
      final legacyMatched = await provider.findTransactionByOrderNumber(45);
      expect(legacyMatched, isNotNull);
      expect(legacyMatched!.id, 45);
    });

    testWidgets('ReceiptDialog displays store orderNumber instead of internal id', (tester) async {
      final tx = SaleTransaction(
        id: 92,
        orderNumber: 90,
        userId: 2,
        totalAmount: 120.0,
        cashReceived: 150.0,
        change: 30.0,
        paymentMethod: 'cash',
        date: DateTime(2026, 11, 15, 11, 30),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReceiptDialog(
              transaction: tx,
              items: const [
                {'product_name': 'Rice 1kg', 'quantity': 2, 'subtotal': 120.0},
              ],
              storeName: 'Store Two',
              storeAddress: 'Manila',
              storePhone: '09171234567',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Receipt #90'), findsOneWidget);
      expect(find.text('ORDER #90'), findsOneWidget);
      expect(find.text('Receipt #92'), findsNothing);
      expect(find.text('ORDER #92'), findsNothing);
    });
  });
}
