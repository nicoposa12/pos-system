import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/transaction.dart';
import '../models/user.dart';

class PdfService {
  static pw.Font? _cachedFontMono;
  static pw.Font? _cachedFontMonoBold;
  static pw.Font? _cachedFontPeso;

  /// Loads authentic monospace fonts with Unicode Peso sign (₱) support.
  /// Falls back gracefully to Courier if custom fonts are unavailable.
  static Future<void> _loadFonts() async {
    if (_cachedFontMono != null &&
        _cachedFontMonoBold != null &&
        _cachedFontPeso != null) {
      return;
    }

    try {
      final regData =
          await rootBundle.load('assets/fonts/RobotoMono-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/RobotoMono-Bold.ttf');
      final pesoData = await rootBundle.load('assets/fonts/Roboto-Peso.ttf');

      _cachedFontMono = pw.Font.ttf(regData);
      _cachedFontMonoBold = pw.Font.ttf(boldData);
      _cachedFontPeso = pw.Font.ttf(pesoData);
      return;
    } catch (_) {}

    try {
      final regFile = File('assets/fonts/RobotoMono-Regular.ttf');
      final boldFile = File('assets/fonts/RobotoMono-Bold.ttf');
      final pesoFile = File('assets/fonts/Roboto-Peso.ttf');

      if (regFile.existsSync() &&
          boldFile.existsSync() &&
          pesoFile.existsSync()) {
        _cachedFontMono =
            pw.Font.ttf(regFile.readAsBytesSync().buffer.asByteData());
        _cachedFontMonoBold =
            pw.Font.ttf(boldFile.readAsBytesSync().buffer.asByteData());
        _cachedFontPeso =
            pw.Font.ttf(pesoFile.readAsBytesSync().buffer.asByteData());
        return;
      }
    } catch (_) {}

    _cachedFontMono ??= pw.Font.courier();
    _cachedFontMonoBold ??= pw.Font.courierBold();
  }

  /// Cleans strings to guarantee compatibility.
  /// Preserves Unicode Peso sign (₱) when the font supports it.
  static String _clean(String? text, {bool keepPeso = true}) {
    if (text == null) return '';
    var s = text
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('•', '*')
        .replaceAll('\u00A0', ' ');
    if (!keepPeso || _cachedFontPeso == null) {
      s = s.replaceAll('₱', 'P');
    }
    return s.trim();
  }

  /// Builds a complete PDF receipt byte buffer matching the Official Cash Receipt dialog.
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
    await _loadFonts();

    final hasPeso = _cachedFontPeso != null;
    final fontFallbackList =
        hasPeso ? <pw.Font>[_cachedFontPeso!] : const <pw.Font>[];
    final currency = hasPeso ? '₱' : 'P';

    final pdf = pw.Document();

    final fontMono = _cachedFontMono ?? pw.Font.courier();
    final fontMonoBold = _cachedFontMonoBold ?? pw.Font.courierBold();

    final dateStr = DateFormat('MMM dd, yyyy').format(transaction.date);
    final timeStr = DateFormat('hh:mm a').format(transaction.date);

    // ── Determine Roll Width & Sizing ──
    final bool is58;
    final double rollWidth;
    final pw.EdgeInsets pageMargin;
    double? targetAspectRatio;

    if (customFormat != null &&
        customFormat.width > 0 &&
        customFormat.width <= 100 * PdfPageFormat.mm) {
      // Hardware printer driver explicitly communicated its physical width
      rollWidth = customFormat.width;
      is58 = rollWidth <= 68 * PdfPageFormat.mm;
      pageMargin = is58
          ? const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10)
          : const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12);
    } else {
      // Use configured paper size preference
      is58 = paperSize.toLowerCase() == '58mm';
      rollWidth = is58 ? 58.0 * PdfPageFormat.mm : 80.0 * PdfPageFormat.mm;
      pageMargin = is58
          ? const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 12)
          : const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14);
      if (customFormat != null &&
          customFormat.width > 100 * PdfPageFormat.mm &&
          customFormat.height.isFinite &&
          customFormat.height > 0) {
        targetAspectRatio = customFormat.width / customFormat.height;
      }
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
    final headerTitleSize = is58 ? 12.0 : 14.0;
    final headerMetaSize = is58 ? 8.0 : 9.0;
    final bodySize = is58 ? 8.5 : 9.5;
    final totalSize = is58 ? 12.0 : 14.0;
    final barcodeW = is58 ? 130.0 : 160.0;
    final barcodeH = is58 ? 30.0 : 36.0;
    final dividerThick = is58 ? 0.75 : 0.9;
    final spacing = is58 ? 3.5 : 4.5;

    final headerTitleStyle = pw.TextStyle(
      font: fontMonoBold,
      fontSize: headerTitleSize,
      color: PdfColors.black,
      fontFallback: fontFallbackList,
    );
    final headerSubStyle = pw.TextStyle(
      font: fontMono,
      fontSize: headerMetaSize,
      color: PdfColors.grey700,
      fontFallback: fontFallbackList,
    );
    final bold = pw.TextStyle(
      font: fontMonoBold,
      fontSize: bodySize,
      color: PdfColors.black,
      fontFallback: fontFallbackList,
    );
    final regular = pw.TextStyle(
      font: fontMono,
      fontSize: bodySize,
      color: PdfColors.black,
      fontFallback: fontFallbackList,
    );
    final regularMuted = pw.TextStyle(
      font: fontMono,
      fontSize: bodySize * 0.9,
      color: PdfColors.grey700,
      fontFallback: fontFallbackList,
    );
    final totalStyle = pw.TextStyle(
      font: fontMonoBold,
      fontSize: totalSize,
      color: PdfColors.black,
      fontFallback: fontFallbackList,
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

    final headerBlock = pw.Column(
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
              pw.SizedBox(height: spacing * 0.3),
              pw.Text('OFFICIAL RECEIPT', style: headerSubStyle),
              if (cleanStoreAddress.isNotEmpty) ...[
                pw.SizedBox(height: spacing * 0.3),
                pw.Text(
                  cleanStoreAddress,
                  style: headerSubStyle,
                  textAlign: pw.TextAlign.center,
                ),
              ],
              pw.SizedBox(height: spacing * 0.25),
              pw.Text('Tel: $phone', style: headerSubStyle),
            ],
          ),
        ),

        pw.SizedBox(height: spacing * 1.0),
        pw.Divider(
          borderStyle: pw.BorderStyle.dashed,
          thickness: dividerThick,
          color: PdfColors.black,
        ),
        pw.SizedBox(height: spacing * 0.4),

        // ── Metadata Rows ──
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'Receipt #${transaction.id ?? 0}',
              style: bold,
            ),
            pw.Container(
              padding: pw.EdgeInsets.symmetric(
                horizontal: is58 ? 5 : 6,
                vertical: 2,
              ),
              decoration: pw.BoxDecoration(
                color: isDebt
                    ? PdfColors.amber100
                    : (isGcash
                        ? PdfColors.teal100
                        : PdfColor.fromHex('#E2E8F0')),
                borderRadius: pw.BorderRadius.circular(3),
              ),
              child: pw.Text(
                isGcash
                    ? 'GCASH'
                    : (isDebt ? 'STORE CREDIT' : 'CASH'),
                style: pw.TextStyle(
                  font: fontMonoBold,
                  fontSize: is58 ? 7.5 : 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: isDebt
                      ? PdfColors.amber900
                      : (isGcash ? PdfColors.teal900 : PdfColors.black),
                  fontFallback: fontFallbackList,
                ),
              ),
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
              pw.Text('Cashier', style: regular),
              pw.Text(cashierName, style: regular),
            ],
          ),
        ],
        if (isDebt && cleanCustomer.isNotEmpty) ...[
          pw.SizedBox(height: spacing * 0.4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Customer', style: bold),
              pw.Text(cleanCustomer, style: bold),
            ],
          ),
        ],

        pw.SizedBox(height: spacing * 0.7),
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
            pw.Text('ITEM / QTY', style: bold),
            pw.Text('AMOUNT', style: bold),
          ],
        ),
        pw.SizedBox(height: spacing * 0.4),
        pw.Divider(
          borderStyle: pw.BorderStyle.dashed,
          thickness: dividerThick,
          color: PdfColors.black,
        ),
        pw.SizedBox(height: spacing * 0.4),
      ],
    );

    // ── Itemized Rows (Matching Official Cash Receipt Layout) ──
    final itemWidgets = items.map<pw.Widget>((item) {
      final rawName = (item['product_name'] ?? 'Item').toString();
      final name = _clean(rawName);
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      final subtotal = ((item['subtotal'] as num?) ?? 0.0).toDouble();
      final unitPrice = qty > 0 ? (subtotal / qty) : subtotal;

      return pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: spacing * 0.35),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(name, style: regular),
                  if (qty > 1) ...[
                    pw.SizedBox(height: 1),
                    pw.Text(
                      '$qty x $currency${unitPrice.toStringAsFixed(2)}',
                      style: regularMuted,
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Text(
              '$currency${subtotal.toStringAsFixed(2)}',
              style: bold,
            ),
          ],
        ),
      );
    }).toList();

    final totalsBlock = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: spacing * 0.6),
        pw.Divider(
          borderStyle: pw.BorderStyle.dashed,
          thickness: dividerThick,
          color: PdfColors.black,
        ),
        pw.SizedBox(height: spacing * 0.5),

        // ── Sub-total & Discount ──
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Sub-total', style: regular),
            pw.Text(
              '$currency${subtotalAmount.toStringAsFixed(2)}',
              style: regular,
            ),
          ],
        ),
        if (transaction.discount > 0) ...[
          pw.SizedBox(height: spacing * 0.35),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Discount', style: regular),
              pw.Text(
                '-$currency${transaction.discount.toStringAsFixed(2)}',
                style: regular,
              ),
            ],
          ),
        ],

        pw.SizedBox(height: spacing * 0.5),

        // ── Prominent TOTAL Bordered Box ──
        pw.Container(
          padding: pw.EdgeInsets.symmetric(vertical: spacing * 0.6),
          decoration: const pw.BoxDecoration(
            border: pw.Border.symmetric(
              horizontal: pw.BorderSide(
                color: PdfColors.black,
                width: 1.0,
              ),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('TOTAL', style: totalStyle),
              pw.Text(
                '$currency${transaction.totalAmount.toStringAsFixed(2)}',
                style: totalStyle,
              ),
            ],
          ),
        ),

        pw.SizedBox(height: spacing * 0.5),

        // ── Payment Tendered & Change ──
        if (isGcash) ...[
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('GCash Paid', style: regular),
              pw.Text(
                '$currency${transaction.totalAmount.toStringAsFixed(2)}',
                style: regular,
              ),
            ],
          ),
          pw.SizedBox(height: spacing * 0.35),
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
                '$currency${transaction.cashReceived.toStringAsFixed(2)}',
                style: regular,
              ),
            ],
          ),
          pw.SizedBox(height: spacing * 0.35),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Pending Balance', style: bold),
              pw.Text(
                '$currency${(transaction.totalAmount - transaction.cashReceived).clamp(0.0, transaction.totalAmount).toStringAsFixed(2)}',
                style: bold,
              ),
            ],
          ),
        ] else ...[
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Cash Tendered', style: regular),
              pw.Text(
                '$currency${transaction.cashReceived.toStringAsFixed(2)}',
                style: regular,
              ),
            ],
          ),
          pw.SizedBox(height: spacing * 0.35),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Change', style: bold),
              pw.Text(
                '$currency${transaction.change.toStringAsFixed(2)}',
                style: bold,
              ),
            ],
          ),
        ],
      ],
    );

    final footerBlock = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: spacing * 1.5),

        // ── Footer Note & Barcode ──
        pw.Center(
          child: pw.Text(
            footerMsg,
            style: pw.TextStyle(
              font: fontMonoBold,
              fontSize: is58 ? 8.5 : 9.5,
              letterSpacing: 0.8,
              fontFallback: fontFallbackList,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
        pw.SizedBox(height: spacing * 1.0),

        pw.Center(
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: 'ORDER-${transaction.id ?? 0}',
                width: barcodeW,
                height: barcodeH,
                drawText: false,
                color: PdfColors.black,
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'ORDER #${transaction.id ?? 0}',
                style: pw.TextStyle(
                  font: fontMono,
                  fontSize: is58 ? 7.5 : 8.5,
                  letterSpacing: 1.2,
                  color: PdfColors.black,
                  fontFallback: fontFallbackList,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: spacing * 1.5),
      ],
    );

    final allSections = <pw.Widget>[
      headerBlock,
      ...itemWidgets,
      totalsBlock,
      footerBlock,
    ];

    if (targetAspectRatio != null &&
        targetAspectRatio > 0 &&
        items.length > 4) {
      // Paginate long orders across multiple pages at the exact readable scale
      // of a 3-item receipt (like Order #12) so items never shrink down.
      final sheetHeight = is58 ? 430.0 : 480.0;
      final sheetWidth = sheetHeight * targetAspectRatio;
      final multiPageFormat = PdfPageFormat(
        sheetWidth,
        sheetHeight,
        marginLeft: pageMargin.left,
        marginRight: pageMargin.right,
        marginTop: pageMargin.top,
        marginBottom: pageMargin.bottom,
      );

      pdf.addPage(
        pw.MultiPage(
          pageFormat: multiPageFormat,
          maxPages: 100,
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          build: (pw.Context context) => allSections,
        ),
      );
    } else {
      pdf.addPage(
        _ReceiptPage(
          pageFormat: pageFormat,
          targetAspectRatio: targetAspectRatio,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: allSections,
            );
          },
        ),
      );
    }

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

/// Custom receipt page that adapts its width/height aspect ratio when rendered
/// in system print spoolers (e.g., Letter / A4 preview on Android/Windows/iOS)
/// so the left and right margins are always 100% equal with no blank gap on
/// the right side.
class _ReceiptPage extends pw.Page {
  final double? targetAspectRatio;

  _ReceiptPage({
    required super.pageFormat,
    required super.build,
    this.targetAspectRatio,
  });

  @override
  PdfPoint layout(
    pw.Widget child,
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    final margin = resolvedMargin!;
    child.layout(context, constraints, parentUsesSize: parentUsesSize);
    assert(child.box != null);

    var width = pageFormat.width == double.infinity
        ? child.box!.width + margin.left + margin.right
        : pageFormat.width;
    var height = pageFormat.height == double.infinity
        ? child.box!.height + margin.top + margin.bottom
        : pageFormat.height;

    final aspect = targetAspectRatio;
    if (aspect != null && aspect > 0 && pageFormat.height == double.infinity) {
      final minWidth = width;
      for (var pass = 0; pass < 3; pass++) {
        width = math.max(minWidth, height * aspect);
        final innerWidth = math.max(10.0, width - margin.horizontal);
        child.layout(
          context,
          pw.BoxConstraints(maxWidth: innerWidth),
          parentUsesSize: parentUsesSize,
        );
        height = child.box!.height + margin.top + margin.bottom;
      }
      width = math.max(minWidth, height * aspect);
      final finalInnerWidth = math.max(10.0, width - margin.horizontal);
      if ((child.box!.width - finalInnerWidth).abs() > 0.1) {
        child.layout(
          context,
          pw.BoxConstraints(maxWidth: finalInnerWidth),
          parentUsesSize: parentUsesSize,
        );
        height = math.max(
          height,
          child.box!.height + margin.top + margin.bottom,
        );
      }
      height = math.max(height, width / aspect);
    }

    final availableWidth = width - margin.horizontal;
    final leftOffset =
        margin.left + math.max(0.0, (availableWidth - child.box!.width) / 2.0);

    child.box = PdfRect(
      leftOffset,
      height - child.box!.height - margin.top,
      child.box!.width,
      child.box!.height,
    );

    return PdfPoint(width, height);
  }
}
