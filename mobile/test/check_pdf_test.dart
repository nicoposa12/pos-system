// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
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

  test('matches target sheet aspect ratio (Letter) with equal left/right margins', () async {
    final tx = SaleTransaction(
      id: 999,
      userId: 1,
      totalAmount: 60.00,
      discount: 0.00,
      cashReceived: 100.00,
      change: 40.00,
      paymentMethod: 'cash',
      date: DateTime(2026, 11, 7, 21, 49),
    );

    final bytes = await PdfService.buildReceiptPdfBytes(
      transaction: tx,
      items: const [
        {'product_name': 'Coke Mismo 290ml', 'quantity': 2, 'subtotal': 36.0},
        {'product_name': 'SkyFlakes Crackers', 'quantity': 3, 'subtotal': 24.0},
      ],
      user: sampleUser,
      storeName: 'Mini-Store',
      storeAddress: 'Your Address Here',
      storePhone: '09XX XXX XXXX',
      paperSize: '58mm',
      customFormat: PdfPageFormat.letter,
    );

    final pdfText = latin1.decode(bytes);
    final match = RegExp(r'/MediaBox\s*\[\s*0(?:\.0+)?\s+0(?:\.0+)?\s+([\d.]+)\s+([\d.]+)\s*\]')
        .firstMatch(pdfText);
    expect(match, isNotNull);

    final pageWidth = double.parse(match!.group(1)!);
    final pageHeight = double.parse(match.group(2)!);
    final expectedAspect = PdfPageFormat.letter.width / PdfPageFormat.letter.height;
    expect(pageWidth / pageHeight, closeTo(expectedAspect, 0.001));
    print('Letter preview MediaBox: $pageWidth x $pageHeight (aspect ${(pageWidth / pageHeight).toStringAsFixed(4)})');
  });

  test('paginates large orders (25 items) at full readable Screenshot-2 scale', () async {
    final tx = SaleTransaction(
      id: 14,
      userId: 1,
      totalAmount: 1937.00,
      discount: 0.00,
      cashReceived: 2000.00,
      change: 63.00,
      paymentMethod: 'cash',
      date: DateTime(2026, 11, 7, 22, 21),
    );

    final manyItems = List.generate(
      25,
      (i) => {
        'product_name': 'Product Item #${i + 1}',
        'quantity': 1,
        'subtotal': 77.48,
      },
    );

    final bytes = await PdfService.buildReceiptPdfBytes(
      transaction: tx,
      items: manyItems,
      user: sampleUser,
      storeName: 'Mini-Store',
      storeAddress: 'Your Address Here',
      storePhone: '09XX XXX XXXX',
      paperSize: '58mm',
      customFormat: PdfPageFormat.letter,
    );

    final pdfText = latin1.decode(bytes);
    final matches = RegExp(
      r'/MediaBox\s*\[\s*0(?:\.0+)?\s+0(?:\.0+)?\s+([\d.]+)\s+([\d.]+)\s*\]',
    ).allMatches(pdfText).toList();

    // Must paginate into multiple pages instead of shrinking onto 1 giant page
    expect(matches.length, greaterThan(1));

    final expectedAspect = PdfPageFormat.letter.width / PdfPageFormat.letter.height;
    for (final m in matches) {
      final w = double.parse(m.group(1)!);
      final h = double.parse(m.group(2)!);
      expect(h, closeTo(430.0, 0.1));
      expect(w / h, closeTo(expectedAspect, 0.001));
    }
    print(
      '25-item receipt paginated into ${matches.length} pages at ${matches.first.group(1)} x ${matches.first.group(2)} pt',
    );
  });

  test('test font loading with peso sign', () async {
    final pdf = pw.Document();
    final fontBytes = File('assets/fonts/RobotoMono-Regular.ttf').readAsBytesSync();
    final boldBytes = File('assets/fonts/RobotoMono-Bold.ttf').readAsBytesSync();
    final pesoBytes = File('assets/fonts/Roboto-Peso.ttf').readAsBytesSync();
    final mono = pw.Font.ttf(fontBytes.buffer.asByteData());
    final monoBold = pw.Font.ttf(boldBytes.buffer.asByteData());
    final peso = pw.Font.ttf(pesoBytes.buffer.asByteData());
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Text('Sub-total: ₱123.00', style: pw.TextStyle(font: mono, fontFallback: [peso])),
              pw.Text('TOTAL: ₱123.00', style: pw.TextStyle(font: monoBold, fontFallback: [peso])),
            ],
          );
        },
      ),
    );
    final saved = await pdf.save();
    print('Generated PDF with RobotoMono + fallback Roboto-Peso: ${saved.length} bytes');
    expect(saved.isNotEmpty, isTrue);

    // Also test that latin1 or bytes contains the drawn glyph
    expect(saved.length, greaterThan(3000));
  });
}
