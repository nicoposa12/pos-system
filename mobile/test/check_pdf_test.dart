// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:tindako/models/transaction.dart';
import 'package:tindako/models/user.dart';
import 'package:tindako/services/pdf_service.dart';

void main() {
  final sampleUser = User(
    id: 1,
    username: 'jiccastore',
    password: 'password123',
    role: 'client',
    fullName: 'Jicca Dela Cruz',
    createdAt: DateTime.now(),
  );

  final sampleItems = [
    {
      'product_name': 'San Miguel Pale Pilsen Can 330ml Extra Cold',
      'quantity': 2,
      'subtotal': 150.00,
    },
    {
      'product_name': 'Mega Sardines in Tomato Sauce 155g',
      'quantity': 4,
      'subtotal': 100.00,
    },
    {
      'product_name': 'SkyFlakes Crackers Single Pack',
      'quantity': 1,
      'subtotal': 8.50,
    },
  ];

  test('generate 58mm thermal receipt PDF bytes cleanly', () async {
    final tx = SaleTransaction(
      id: 101,
      userId: 1,
      totalAmount: 248.50,
      discount: 10.00,
      cashReceived: 500.00,
      change: 251.50,
      paymentMethod: 'cash',
      date: DateTime(2026, 11, 7, 20, 30),
    );

    final bytes = await PdfService.buildReceiptPdfBytes(
      transaction: tx,
      items: sampleItems,
      user: sampleUser,
      storeName: 'Jicca Sari-Sari Store',
      storeAddress: 'Barangay 123, Manila, Philippines',
      storePhone: '0917 123 4567',
      paperSize: '58mm',
      receiptFooterNote: 'Salamat sa pagbili! Balik po kayo!',
    );

    expect(bytes.isNotEmpty, isTrue);
    expect(bytes.length, greaterThan(1000));
    print('58mm Receipt generated successfully: ${bytes.length} bytes');
  });

  test('generate 80mm thermal receipt PDF bytes cleanly', () async {
    final tx = SaleTransaction(
      id: 102,
      userId: 1,
      totalAmount: 258.50,
      discount: 0.00,
      cashReceived: 258.50,
      change: 0.00,
      paymentMethod: 'gcash',
      date: DateTime(2026, 11, 7, 20, 35),
    );

    final bytes = await PdfService.buildReceiptPdfBytes(
      transaction: tx,
      items: sampleItems,
      user: sampleUser,
      storeName: 'Jicca SuperMart & Wholesale',
      storeAddress: '123 Commercial St., Quezon City',
      storePhone: '0918 987 6543',
      paperSize: '80mm',
      receiptFooterNote: 'Thank you for shopping with us!',
    );

    expect(bytes.isNotEmpty, isTrue);
    expect(bytes.length, greaterThan(1000));
    print('80mm Receipt generated successfully: ${bytes.length} bytes');
  });

  test('generate Debt / Store Credit receipt with customer name', () async {
    final tx = SaleTransaction(
      id: 103,
      userId: 1,
      totalAmount: 258.50,
      discount: 0.00,
      cashReceived: 100.00,
      change: 0.00,
      paymentMethod: 'debt',
      date: DateTime(2026, 11, 7, 20, 40),
    );

    final bytes = await PdfService.buildReceiptPdfBytes(
      transaction: tx,
      items: sampleItems,
      user: sampleUser,
      storeName: 'Jicca Store',
      storeAddress: 'Manila',
      storePhone: '0912 345 6789',
      customerName: 'Aling Maria (Purok 4)',
      paperSize: '58mm',
    );

    expect(bytes.isNotEmpty, isTrue);
    expect(bytes.length, greaterThan(1000));
    print('Debt Receipt generated successfully: ${bytes.length} bytes');
  });
}
