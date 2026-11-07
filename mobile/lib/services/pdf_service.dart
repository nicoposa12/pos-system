import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/transaction.dart';
import '../models/user.dart';

class PdfService {
  /// Cleans strings to guarantee pure ASCII/WinAnsi characters.
  /// Prevents glyph dropouts and printer buffer errors across thermal heads.
  static String _clean(String? text) {
    if (text == null) return '';
    return text
        .replaceAll('₱', 'P')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('•', '*')
        .replaceAll('\u00A0', ' ')
        .trim();
  }

  /// Builds a complete PDF receipt byte buffer for 58mm or 80mm thermal rolls.
  static Future<Uint8List> buildReceiptPdfBytes({
    required SaleTransaction transaction,
    required List<Map<String, dynamic>> items,
    required User? user,
    required String storeName,
    required String storeAddress,
    String? storePhone,
    String? customerName,
    String? businessPhotoPath,
    String? receiptFooterNote,
    String paperSize = '58mm',
    PdfPageFormat? customFormat,
  }) async {
    final pdf = pw.Document();

    final fontMono = pw.Font.courier();
    final fontMonoBold = pw.Font.courierBold();

    final dateStr = DateFormat('MM-dd-yyyy').format(transaction.date);
    final timeStr = DateFormat('hh:mm a').format(transaction.date);

    // ── Determine Roll Width & Sizing ──
    final bool is58;
    final double rollWidth;
    final pw.EdgeInsets pageMargin;

    if (customFormat != null &&
        customFormat.width > 0 &&
        customFormat.width <= 100 * PdfPageFormat.mm) {
      // Hardware printer driver explicitly communicated its physical width
      rollWidth = customFormat.width;
      is58 = rollWidth <= 68 * PdfPageFormat.mm;
      pageMargin = is58
          ? const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10)
          : const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12);
    } else {
      // Use configured paper size preference
      is58 = paperSize.toLowerCase() == '58mm';
      rollWidth = is58 ? 58.0 * PdfPageFormat.mm : 80.0 * PdfPageFormat.mm;
      pageMargin = is58
          ? const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10)
          : const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12);
    }

    final pageFormat = PdfPageFormat(
      rollWidth,
      double.infinity,
      marginLeft: pageMargin.left,
      marginRight: pageMargin.right,
      marginTop: pageMargin.top,
      marginBottom: pageMargin.bottom,
    );

    // Dynamic typography scaling based on roll format
    final headerTitleSize = is58 ? 11.5 : 13.5;
    final headerMetaSize = is58 ? 7.5 : 8.5;
    final bodySize = is58 ? 7.8 : 8.8;
    final itemNameSize = is58 ? 8.5 : 9.5;
    final totalSize = is58 ? 11.5 : 13.5;
    final barcodeW = is58 ? 112.0 : 148.0;
    final barcodeH = is58 ? 28.0 : 34.0;
    final dividerThick = is58 ? 0.75 : 0.9;
    final spacing = is58 ? 3.0 : 4.0;

    final headerTitleStyle = pw.TextStyle(
      font: fontMonoBold,
      fontSize: headerTitleSize,
      color: PdfColors.black,
    );
    final headerSubStyle = pw.TextStyle(
      font: fontMono,
      fontSize: headerMetaSize,
      color: PdfColors.black,
    );
    final bold = pw.TextStyle(
      font: fontMonoBold,
      fontSize: bodySize,
      color: PdfColors.black,
    );
    final regular = pw.TextStyle(
      font: fontMono,
      fontSize: bodySize,
      color: PdfColors.black,
    );
    final itemNameStyle = pw.TextStyle(
      font: fontMonoBold,
      fontSize: itemNameSize,
      color: PdfColors.black,
    );
    final totalStyle = pw.TextStyle(
      font: fontMonoBold,
      fontSize: totalSize,
      color: PdfColors.black,
    );

    final cleanStoreName = _clean(storeName).isNotEmpty
        ? _clean(storeName).toUpperCase()
        : 'TINDAKO STORE';
    final cleanStoreAddress = _clean(storeAddress);
    final phone = _clean(storePhone).isNotEmpty
        ? _clean(storePhone)
        : '09XX XXX XXXX';
    final footerMsg = _clean(receiptFooterNote).isNotEmpty
        ? _clean(receiptFooterNote).toUpperCase()
        : 'THANK YOU FOR YOUR PURCHASE!';

    // Optional store logo image loading
    pw.MemoryImage? logoImage;
    if (businessPhotoPath != null && businessPhotoPath.trim().isNotEmpty) {
      try {
        final path = businessPhotoPath.trim();
        if (path.startsWith('http://') || path.startsWith('https://')) {
          final res = await Dio().get<List<int>>(
            path,
            options: Options(
              responseType: ResponseType.bytes,
              receiveTimeout: const Duration(seconds: 3),
              sendTimeout: const Duration(seconds: 3),
            ),
          );
          if (res.data != null && res.data!.isNotEmpty) {
            logoImage = pw.MemoryImage(Uint8List.fromList(res.data!));
          }
        } else {
          final file = File(path);
          if (file.existsSync()) {
            final bytes = await file.readAsBytes();
            if (bytes.isNotEmpty) {
              logoImage = pw.MemoryImage(bytes);
            }
          }
        }
      } catch (_) {
        // Safe fallback without logo
      }
    }

    final isGcash = transaction.paymentMethod.toLowerCase() == 'gcash';
    final isDebt = transaction.paymentMethod.toLowerCase() == 'debt' ||
        transaction.paymentMethod.toLowerCase() == 'pending';
    final cashierName = _clean(user?.fullName);
    final cleanCustomer = _clean(customerName);

    final subtotalAmount = transaction.totalAmount + transaction.discount;
    final totalUnits = items.fold<int>(
      0,
      (sum, i) => sum + ((i['quantity'] as num?)?.toInt() ?? 1),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // ── Header Section ──
              if (logoImage != null) ...[
                pw.Center(
                  child: pw.Padding(
                    padding: pw.EdgeInsets.only(bottom: spacing),
                    child: pw.Image(
                      logoImage,
                      width: is58 ? 36 : 46,
                      height: is58 ? 36 : 46,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ),
              ],
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      cleanStoreName,
                      style: headerTitleStyle,
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: spacing * 0.4),
                    pw.Text('OFFICIAL RECEIPT', style: headerSubStyle),
                    if (cleanStoreAddress.isNotEmpty) ...[
                      pw.SizedBox(height: spacing * 0.3),
                      pw.Text(
                        cleanStoreAddress,
                        style: headerSubStyle,
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                    pw.SizedBox(height: spacing * 0.3),
                    pw.Text('Tel: $phone', style: headerSubStyle),
                  ],
                ),
              ),

              pw.SizedBox(height: spacing * 1.2),
              pw.Divider(
                borderStyle: pw.BorderStyle.dashed,
                thickness: dividerThick,
                color: PdfColors.black,
              ),
              pw.SizedBox(height: spacing * 0.4),

              // ── Metadata Rows ──
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Order #${transaction.id ?? 0}', style: bold),
                  pw.Text(
                    isGcash
                        ? '[GCASH]'
                        : (isDebt ? '[STORE CREDIT]' : '[CASH]'),
                    style: bold,
                  ),
                ],
              ),
              pw.SizedBox(height: spacing * 0.4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(dateStr, style: regular),
                  pw.Text(timeStr, style: regular),
                ],
              ),
              if (cashierName.isNotEmpty) ...[
                pw.SizedBox(height: spacing * 0.4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Cashier:', style: regular),
                    pw.Text(cashierName, style: regular),
                  ],
                ),
              ],
              if (isDebt && cleanCustomer.isNotEmpty) ...[
                pw.SizedBox(height: spacing * 0.4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Customer:', style: bold),
                    pw.Text(cleanCustomer, style: bold),
                  ],
                ),
              ],

              pw.SizedBox(height: spacing * 0.8),
              pw.Divider(
                borderStyle: pw.BorderStyle.dashed,
                thickness: dividerThick,
                color: PdfColors.black,
              ),
              pw.SizedBox(height: spacing * 0.4),

              // ── Items Table Header ──
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('ITEM DESCRIPTION', style: bold),
                  pw.Text('AMOUNT', style: bold),
                ],
              ),
              pw.SizedBox(height: spacing * 0.4),
              pw.Divider(
                borderStyle: pw.BorderStyle.dashed,
                thickness: dividerThick,
                color: PdfColors.black,
              ),
              pw.SizedBox(height: spacing * 0.6),

              // ── Itemized Rows (Anti-Collision Format) ──
              ...items.map((item) {
                final rawName = (item['product_name'] ?? 'Item').toString();
                final name = _clean(rawName);
                final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                final subtotal =
                    ((item['subtotal'] as num?) ?? 0.0).toDouble();
                final unitPrice = qty > 0 ? (subtotal / qty) : subtotal;

                return pw.Padding(
                  padding: pw.EdgeInsets.symmetric(vertical: spacing * 0.4),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      // Item name (wraps smoothly to multiple lines if long)
                      pw.Text(name, style: itemNameStyle),
                      pw.SizedBox(height: 1.5),
                      // Quantity x Unit Price ... Line Subtotal
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(left: 4),
                            child: pw.Text(
                              '$qty x P${unitPrice.toStringAsFixed(2)}',
                              style: regular,
                            ),
                          ),
                          pw.Text(
                            'P${subtotal.toStringAsFixed(2)}',
                            style: bold,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              pw.SizedBox(height: spacing * 0.8),
              pw.Divider(
                borderStyle: pw.BorderStyle.dashed,
                thickness: dividerThick,
                color: PdfColors.black,
              ),
              pw.SizedBox(height: spacing * 0.6),

              // ── Subtotal & Discount ──
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Sub-total', style: regular),
                  pw.Text('P${subtotalAmount.toStringAsFixed(2)}',
                      style: regular),
                ],
              ),
              if (transaction.discount > 0) ...[
                pw.SizedBox(height: spacing * 0.4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Discount', style: regular),
                    pw.Text(
                      '-P${transaction.discount.toStringAsFixed(2)}',
                      style: regular,
                    ),
                  ],
                ),
              ],

              pw.SizedBox(height: spacing * 0.6),

              // ── Prominent TOTAL Bordered Box ──
              pw.Container(
                padding: pw.EdgeInsets.symmetric(vertical: spacing * 0.8),
                decoration: const pw.BoxDecoration(
                  border: pw.Border.symmetric(
                    horizontal: pw.BorderSide(
                      color: PdfColors.black,
                      width: 1.2,
                    ),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOTAL', style: totalStyle),
                    pw.Text(
                      'P${transaction.totalAmount.toStringAsFixed(2)}',
                      style: totalStyle,
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: spacing * 0.6),

              // ── Payment Tendered & Balance / Change ──
              if (isGcash) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('GCash Paid', style: regular),
                    pw.Text(
                      'P${transaction.totalAmount.toStringAsFixed(2)}',
                      style: bold,
                    ),
                  ],
                ),
                pw.SizedBox(height: spacing * 0.3),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Payment Status', style: regular),
                    pw.Text('COMPLETED', style: bold),
                  ],
                ),
              ] else if (isDebt) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Deposit / Paid', style: regular),
                    pw.Text(
                      'P${transaction.cashReceived.toStringAsFixed(2)}',
                      style: regular,
                    ),
                  ],
                ),
                pw.SizedBox(height: spacing * 0.3),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Balance Due', style: bold),
                    pw.Text(
                      'P${(transaction.totalAmount - transaction.cashReceived).clamp(0.0, transaction.totalAmount).toStringAsFixed(2)}',
                      style: bold,
                    ),
                  ],
                ),
              ] else ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Cash Received', style: regular),
                    pw.Text(
                      'P${transaction.cashReceived.toStringAsFixed(2)}',
                      style: regular,
                    ),
                  ],
                ),
                pw.SizedBox(height: spacing * 0.3),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Change', style: bold),
                    pw.Text(
                      'P${transaction.change.toStringAsFixed(2)}',
                      style: bold,
                    ),
                  ],
                ),
              ],

              pw.SizedBox(height: spacing * 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Item Count', style: regular),
                  pw.Text(
                    '$totalUnits units (${items.length} items)',
                    style: regular,
                  ),
                ],
              ),

              pw.SizedBox(height: spacing * 1.4),
              pw.Divider(
                borderStyle: pw.BorderStyle.dashed,
                thickness: dividerThick,
                color: PdfColors.black,
              ),
              pw.SizedBox(height: spacing * 1.2),

              // ── Footer Note & Barcode ──
              pw.Center(
                child: pw.Text(
                  footerMsg,
                  style: pw.TextStyle(
                    font: fontMonoBold,
                    fontSize: is58 ? 8.0 : 9.0,
                    letterSpacing: 0.8,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: spacing * 1.2),

              pw.Center(
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.code128(),
                      data: 'ORD-${transaction.id ?? 0}',
                      width: barcodeW,
                      height: barcodeH,
                      drawText: false,
                      color: PdfColors.black,
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      '* ORDER #${transaction.id ?? 0} *',
                      style: pw.TextStyle(
                        font: fontMonoBold,
                        fontSize: is58 ? 7.5 : 8.5,
                        letterSpacing: 1.0,
                        color: PdfColors.black,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: spacing * 1.5),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Spools and prints receipt directly to thermal printers, bluetooth rolls, or system print dialog.
  static Future<void> generateAndPrintReceipt({
    required SaleTransaction transaction,
    required List<Map<String, dynamic>> items,
    required User? user,
    required String storeName,
    required String storeAddress,
    String? storePhone,
    String? customerName,
    String? businessPhotoPath,
    String? receiptFooterNote,
    String paperSize = '58mm',
  }) async {
    final defaultRoll = (paperSize == '80mm')
        ? PdfPageFormat.roll80
        : PdfPageFormat(58 * PdfPageFormat.mm, double.infinity);

    await Printing.layoutPdf(
      name: 'receipt_${transaction.id}.pdf',
      format: defaultRoll,
      onLayout: (PdfPageFormat format) async {
        return buildReceiptPdfBytes(
          transaction: transaction,
          items: items,
          user: user,
          storeName: storeName,
          storeAddress: storeAddress,
          storePhone: storePhone,
          customerName: customerName,
          businessPhotoPath: businessPhotoPath,
          receiptFooterNote: receiptFooterNote,
          paperSize: paperSize,
          customFormat: format,
        );
      },
    );
  }

  /// Generates clean sales summary reports on standard A4 format.
  static Future<void> generateSalesReport({
    required List<SaleTransaction> transactions,
    required String periodLabel,
    required String storeName,
    required String storeAddress,
  }) async {
    final pdf = pw.Document();
    final total = transactions.fold(0.0, (sum, t) => sum + t.totalAmount);
    final dateGenerated = DateFormat(
      'MMM d, yyyy - h:mm a',
    ).format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _clean(storeName).toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      _clean(storeAddress),
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'SALES REPORT',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo,
                      ),
                    ),
                    pw.Text(
                      'Generated: $dateGenerated',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 20),

            // Summary
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Report Period:',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      _clean(periodLabel),
                      style: const pw.TextStyle(fontSize: 14),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Total Revenue:',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'P${total.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 30),

            // Table
            pw.TableHelper.fromTextArray(
              context: context,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
              cellHeight: 30,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerRight,
              },
              headerAlignment: pw.Alignment.centerLeft,
              data: <List<String>>[
                <String>['Transaction ID', 'Date & Time', 'Amount'],
                ...transactions.map(
                  (t) => [
                    '#${t.id}',
                    DateFormat('MMM d, yyyy - h:mm a').format(t.date),
                    'P${t.totalAmount.toStringAsFixed(2)}',
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text(
                  'Transaction Count: ${transactions.length}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'sales_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }
}
