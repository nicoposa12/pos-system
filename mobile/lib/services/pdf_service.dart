import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/transaction.dart';
import '../models/user.dart';
import '../models/product.dart';

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
              'Receipt #${transaction.displayOrderNumber ?? 0}',
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
      final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
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
                  if ((qty - 1.0).abs() > 0.0001) ...[
                    pw.SizedBox(height: 1),
                    pw.Text(
                      '${formatQuantity(qty)} x $currency${unitPrice.toStringAsFixed(2)}',
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
                data: 'ORDER-${transaction.displayOrderNumber ?? 0}',
                width: barcodeW,
                height: barcodeH,
                drawText: false,
                color: PdfColors.black,
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'ORDER #${transaction.displayOrderNumber ?? 0}',
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
      name: 'receipt_${transaction.displayOrderNumber ?? transaction.id}.pdf',
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

  /// Builds clean sales summary report PDF bytes on standard A4 format,
  /// including Est. Profit summary and per-order Profit column when cost data exists.
  static Future<Uint8List> buildSalesReportPdfBytes({
    required List<SaleTransaction> transactions,
    required String periodLabel,
    required String storeName,
    required String storeAddress,
  }) async {
    await _loadFonts();

    final hasPeso = _cachedFontPeso != null;
    final fontFallbackList =
        hasPeso ? <pw.Font>[_cachedFontPeso!] : const <pw.Font>[];
    final currency = hasPeso ? '₱' : 'P';

    final fontRegular = _cachedFontMono ?? pw.Font.helvetica();
    final fontBold = _cachedFontMonoBold ?? pw.Font.helveticaBold();

    final moneyFmt = NumberFormat('#,##0.00');
    final total = transactions.fold(0.0, (sum, t) => sum + t.totalAmount);
    final hasProfitData = transactions.any((t) => t.totalProfit != null);
    final totalProfit = transactions.fold(
      0.0,
      (sum, t) => sum + (t.totalProfit ?? 0.0),
    );
    final dateGenerated = DateFormat(
      'MMM d, yyyy - h:mm a',
    ).format(DateTime.now());

    String formatMoney(double value) => '$currency${moneyFmt.format(value)}';
    String formatSignedMoney(double value) =>
        '${value < 0 ? '-' : '+'}$currency${moneyFmt.format(value.abs())}';

    final navyColor = PdfColor.fromHex('#131D2E');
    final tealColor = PdfColor.fromHex('#0D9488');
    final roseColor = PdfColor.fromHex('#E11D48');

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
        fontFallback: fontFallbackList,
      ),
    );

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
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        _clean(storeName).toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: navyColor,
                        ),
                      ),
                      pw.Text(
                        _clean(storeAddress),
                        style: const pw.TextStyle(fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'SALES REPORT',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo,
                      ),
                    ),
                    pw.Text(
                      'Generated: $dateGenerated',
                      style: const pw.TextStyle(fontSize: 9.5),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.SizedBox(height: 16),

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
                      style: const pw.TextStyle(fontSize: 13),
                    ),
                  ],
                ),
                pw.Row(
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'Total Revenue:',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          formatMoney(total),
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.orange,
                          ),
                        ),
                      ],
                    ),
                    if (hasProfitData) ...[
                      pw.SizedBox(width: 24),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'Est. Profit:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(
                            formatSignedMoney(totalProfit),
                            style: pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                              color: totalProfit < 0 ? roseColor : tealColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // Table
            pw.TableHelper.fromTextArray(
              context: context,
              headerStyle: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: navyColor),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellHeight: 28,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.centerRight,
                if (hasProfitData) 4: pw.Alignment.centerRight,
              },
              headerAlignment: pw.Alignment.centerLeft,
              data: <List<String>>[
                <String>[
                  'Order #',
                  'Date & Time',
                  'Payment',
                  'Amount',
                  if (hasProfitData) 'Profit',
                ],
                ...transactions.map(
                  (t) => [
                    '#${t.displayOrderNumber ?? t.id}',
                    DateFormat('MMM d, yyyy - h:mm a').format(t.date),
                    t.paymentMethod.toUpperCase(),
                    formatMoney(t.totalAmount),
                    if (hasProfitData)
                      t.totalProfit != null
                          ? formatSignedMoney(t.totalProfit!)
                          : '-',
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 18),
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

    return pdf.save();
  }

  /// Generates clean sales summary reports on standard A4 format.
  static Future<void> generateSalesReport({
    required List<SaleTransaction> transactions,
    required String periodLabel,
    required String storeName,
    required String storeAddress,
  }) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) => buildSalesReportPdfBytes(
        transactions: transactions,
        periodLabel: periodLabel,
        storeName: storeName,
        storeAddress: storeAddress,
      ),
      name: 'sales_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  /// Builds an A4 PDF byte buffer for the Best Sellers product leaderboard
  /// (Daily, Weekly, Monthly, Yearly, or All Time), including revenue, units
  /// sold, remaining inventory stock, and estimated profit when cost data exists.
  static Future<Uint8List> buildBestSellersReportPdfBytes({
    required List<Map<String, dynamic>> items,
    required String periodTypeLabel,
    required String periodRangeLabel,
    required String sortLabel,
    required String storeName,
    required String storeAddress,
    String? storePhone,
    Map<int, Product> productsById = const {},
  }) async {
    await _loadFonts();

    final hasPeso = _cachedFontPeso != null;
    final fontFallbackList =
        hasPeso ? <pw.Font>[_cachedFontPeso!] : const <pw.Font>[];
    final currency = hasPeso ? '₱' : 'P';

    final fontRegular = _cachedFontMono ?? pw.Font.helvetica();
    final fontBold = _cachedFontMonoBold ?? pw.Font.helveticaBold();

    final moneyFmt = NumberFormat('#,##0.00');
    final dateGenerated = DateFormat(
      'MMM d, yyyy - h:mm a',
    ).format(DateTime.now());

    final totalUnits = items.fold<double>(
      0.0,
      (sum, item) => sum + ((item['total_sold'] as num?)?.toDouble() ?? 0.0),
    );
    final totalRevenue = items.fold<double>(
      0.0,
      (sum, item) =>
          sum + ((item['total_revenue'] as num?)?.toDouble() ?? 0.0),
    );
    final hasProfitData = items.any((item) => item['has_cost_data'] == true);
    final totalProfit = items.fold<double>(
      0.0,
      (sum, item) => item['has_cost_data'] == true
          ? sum + ((item['total_profit'] as num?)?.toDouble() ?? 0.0)
          : sum,
    );
    final costedRevenue = items.fold<double>(
      0.0,
      (sum, item) => item['has_cost_data'] == true
          ? sum + ((item['total_revenue'] as num?)?.toDouble() ?? 0.0)
          : sum,
    );

    final navyColor = PdfColor.fromHex('#131D2E');
    final orangeColor = PdfColor.fromHex('#F97316');
    final tealColor = PdfColor.fromHex('#0D9488');
    final roseColor = PdfColor.fromHex('#E11D48');
    final borderColor = PdfColor.fromHex('#E2E8F0');
    final mutedColor = PdfColor.fromHex('#64748B');
    final softBg = PdfColor.fromHex('#F8FAFC');

    String formatMoney(double value) => '$currency${moneyFmt.format(value)}';
    String formatSignedMoney(double value) =>
        '${value < 0 ? '-' : '+'}$currency${moneyFmt.format(value.abs())}';

    final tableHeaders = <String>[
      '#',
      'Product',
      'Category',
      'Sold',
      'Stock Left',
      'Revenue',
      if (hasProfitData) 'Profit',
    ];

    final tableRows = <List<String>>[];
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final productId = (item['product_id'] as num?)?.toInt() ?? 0;
      final product = productId > 0 ? productsById[productId] : null;
      final name = _clean((item['name'] ?? 'Item').toString());
      final rawCat = (item['category'] ?? product?.category)?.toString().trim();
      final category = (rawCat != null && rawCat.isNotEmpty)
          ? _clean(rawCat)
          : '-';
      final unit = product?.unit.trim();
      final unitSuffix = (unit != null && unit.isNotEmpty) ? ' $unit' : '';
      final sold = (item['total_sold'] as num?)?.toDouble() ?? 0.0;
      final revenue = (item['total_revenue'] as num?)?.toDouble() ?? 0.0;
      final stockText = product == null
          ? '-'
          : (product.stock <= 0
                ? 'Out of stock'
                : '${formatQuantity(product.stock)}$unitSuffix');
      final hasItemCost = item['has_cost_data'] == true;
      final itemProfit = hasItemCost
          ? ((item['total_profit'] as num?)?.toDouble() ?? 0.0)
          : null;

      tableRows.add([
        '${i + 1}',
        name,
        category,
        '${formatQuantity(sold)}$unitSuffix',
        stockText,
        formatMoney(revenue),
        if (hasProfitData)
          itemProfit != null ? formatSignedMoney(itemProfit) : '-',
      ]);
    }

    final columnWidths = hasProfitData
        ? <int, pw.TableColumnWidth>{
            0: const pw.FixedColumnWidth(26),
            1: const pw.FlexColumnWidth(2.6),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FlexColumnWidth(1.1),
            4: const pw.FlexColumnWidth(1.2),
            5: const pw.FlexColumnWidth(1.4),
            6: const pw.FlexColumnWidth(1.3),
          }
        : <int, pw.TableColumnWidth>{
            0: const pw.FixedColumnWidth(28),
            1: const pw.FlexColumnWidth(3.0),
            2: const pw.FlexColumnWidth(1.7),
            3: const pw.FlexColumnWidth(1.2),
            4: const pw.FlexColumnWidth(1.3),
            5: const pw.FlexColumnWidth(1.5),
          };

    final cellAlignments = <int, pw.Alignment>{
      0: pw.Alignment.center,
      1: pw.Alignment.centerLeft,
      2: pw.Alignment.centerLeft,
      3: pw.Alignment.centerRight,
      4: pw.Alignment.centerRight,
      5: pw.Alignment.centerRight,
      if (hasProfitData) 6: pw.Alignment.centerRight,
    };

    pw.Widget buildSummaryBox({
      required String label,
      required String value,
      PdfColor? valueColor,
      String? subtext,
    }) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: pw.BoxDecoration(
            color: softBg,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            border: pw.Border.all(color: borderColor, width: 0.8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: mutedColor,
                  letterSpacing: 0.4,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: valueColor ?? navyColor,
                ),
              ),
              if (subtext != null) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  subtext,
                  style: pw.TextStyle(fontSize: 8, color: mutedColor),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final cleanStore = _clean(storeName).isNotEmpty
        ? _clean(storeName)
        : 'TindaKo POS';
    final cleanAddress = _clean(storeAddress);
    final cleanPhone = _clean(storePhone);

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
        fontFallback: fontFallbackList,
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 32),
        footer: (pw.Context context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 12),
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: borderColor, width: 0.7),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '$cleanStore - Best Sellers Report (${_clean(periodTypeLabel)})',
                style: pw.TextStyle(fontSize: 8.5, color: mutedColor),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 8.5, color: mutedColor),
              ),
            ],
          ),
        ),
        build: (pw.Context context) => [
          // Header
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      cleanStore.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: navyColor,
                      ),
                    ),
                    if (cleanAddress.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        cleanAddress,
                        style: pw.TextStyle(fontSize: 9.5, color: mutedColor),
                      ),
                    ],
                    if (cleanPhone.isNotEmpty) ...[
                      pw.SizedBox(height: 1),
                      pw.Text(
                        cleanPhone,
                        style: pw.TextStyle(fontSize: 9.5, color: mutedColor),
                      ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: pw.BoxDecoration(
                      color: orangeColor,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                    ),
                    child: pw.Text(
                      'BEST SELLERS (${_clean(periodTypeLabel).toUpperCase()})',
                      style: pw.TextStyle(
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    _clean(periodRangeLabel),
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: navyColor,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Sorted by: ${_clean(sortLabel)}',
                    style: pw.TextStyle(fontSize: 8.5, color: mutedColor),
                  ),
                  pw.Text(
                    'Generated: $dateGenerated',
                    style: pw.TextStyle(fontSize: 8.5, color: mutedColor),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Divider(color: borderColor, thickness: 1),
          pw.SizedBox(height: 12),

          // Summary KPI Strip
          pw.Row(
            children: [
              buildSummaryBox(
                label: 'Product Sales',
                value: formatMoney(totalRevenue),
                valueColor: orangeColor,
              ),
              pw.SizedBox(width: 8),
              if (hasProfitData) ...[
                buildSummaryBox(
                  label: 'Est. Profit',
                  value: formatSignedMoney(totalProfit),
                  valueColor: totalProfit < 0 ? roseColor : tealColor,
                  subtext: costedRevenue > 0
                      ? '${(totalProfit / costedRevenue * 100).toStringAsFixed(1)}% margin'
                      : null,
                ),
                pw.SizedBox(width: 8),
              ],
              buildSummaryBox(
                label: 'Units Sold',
                value: formatQuantity(totalUnits),
              ),
              pw.SizedBox(width: 8),
              buildSummaryBox(
                label: 'Products',
                value: '${items.length}',
              ),
            ],
          ),
          pw.SizedBox(height: 16),

          // Ranked Products Table
          if (tableRows.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(24),
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                color: softBg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: borderColor),
              ),
              child: pw.Text(
                'No product sales recorded for this period.',
                style: pw.TextStyle(fontSize: 11, color: mutedColor),
              ),
            )
          else
            pw.TableHelper.fromTextArray(
              context: context,
              headers: tableHeaders,
              data: tableRows,
              columnWidths: columnWidths,
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: navyColor),
              headerAlignment: pw.Alignment.centerLeft,
              headerAlignments: cellAlignments,
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 6,
              ),
              cellAlignments: cellAlignments,
              oddRowDecoration: pw.BoxDecoration(color: softBg),
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(
                  color: borderColor,
                  width: 0.5,
                ),
                bottom: pw.BorderSide(color: borderColor, width: 0.8),
              ),
            ),

          if (tableRows.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: pw.BoxDecoration(
                color: softBg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: borderColor, width: 0.8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL (${items.length} ${items.length == 1 ? 'product' : 'products'} | ${formatQuantity(totalUnits)} units sold)',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: navyColor,
                    ),
                  ),
                  pw.Row(
                    children: [
                      pw.Text(
                        'Sales: ${formatMoney(totalRevenue)}',
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: orangeColor,
                        ),
                      ),
                      if (hasProfitData) ...[
                        pw.SizedBox(width: 12),
                        pw.Text(
                          'Profit: ${formatSignedMoney(totalProfit)}',
                          style: pw.TextStyle(
                            fontSize: 9.5,
                            fontWeight: pw.FontWeight.bold,
                            color: totalProfit < 0 ? roseColor : tealColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  /// Opens the native print / PDF preview dialog for a Best Sellers report.
  static Future<void> generateBestSellersReport({
    required List<Map<String, dynamic>> items,
    required String periodTypeLabel,
    required String periodRangeLabel,
    required String sortLabel,
    required String storeName,
    required String storeAddress,
    String? storePhone,
    Map<int, Product> productsById = const {},
    String? fileName,
  }) async {
    final safeName = fileName ??
        'best_sellers_${periodTypeLabel.toLowerCase().replaceAll(' ', '_')}.pdf';
    await Printing.layoutPdf(
      name: safeName,
      format: PdfPageFormat.a4,
      onLayout: (PdfPageFormat format) => buildBestSellersReportPdfBytes(
        items: items,
        periodTypeLabel: periodTypeLabel,
        periodRangeLabel: periodRangeLabel,
        sortLabel: sortLabel,
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        productsById: productsById,
      ),
    );
  }

  /// Saves the Best Sellers PDF directly via the OS save dialog on desktop,
  /// or opens the native share sheet on mobile/web. Returns the saved file path
  /// (desktop), `'shared'` (mobile/web), or `null` if cancelled.
  static Future<String?> saveOrShareBestSellersReport({
    required List<Map<String, dynamic>> items,
    required String periodTypeLabel,
    required String periodRangeLabel,
    required String sortLabel,
    required String storeName,
    required String storeAddress,
    String? storePhone,
    Map<int, Product> productsById = const {},
    String? fileName,
  }) async {
    final safeName = fileName ??
        'best_sellers_${periodTypeLabel.toLowerCase().replaceAll(' ', '_')}.pdf';
    final bytes = await buildBestSellersReportPdfBytes(
      items: items,
      periodTypeLabel: periodTypeLabel,
      periodRangeLabel: periodRangeLabel,
      sortLabel: sortLabel,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      productsById: productsById,
    );

    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (isDesktop) {
      final selectedPath = await FilePicker.saveFile(
        dialogTitle: 'Save Best Sellers PDF Report',
        fileName: safeName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (selectedPath == null || selectedPath.trim().isEmpty) return null;
      final finalPath = selectedPath.toLowerCase().endsWith('.pdf')
          ? selectedPath
          : '$selectedPath.pdf';
      await File(finalPath).writeAsBytes(bytes, flush: true);
      return finalPath;
    }

    await Printing.sharePdf(bytes: bytes, filename: safeName);
    return 'shared';
  }

  /// Builds an A4 PDF byte buffer for the store's Inventory catalog filtered by
  /// stock status (`All Items`, `Healthy`, `Low Stock`, or `Out of Stock`).
  static Future<Uint8List> buildInventoryReportPdfBytes({
    required List<Product> products,
    required String filterLabel,
    required String sortLabel,
    String? categoryLabel,
    required String storeName,
    required String storeAddress,
    String? storePhone,
  }) async {
    await _loadFonts();

    final hasPeso = _cachedFontPeso != null;
    final fontFallbackList =
        hasPeso ? <pw.Font>[_cachedFontPeso!] : const <pw.Font>[];
    final currency = hasPeso ? '₱' : 'P';

    final fontRegular = _cachedFontMono ?? pw.Font.helvetica();
    final fontBold = _cachedFontMonoBold ?? pw.Font.helveticaBold();

    final moneyFmt = NumberFormat('#,##0.00');
    final dateGenerated = DateFormat(
      'MMM d, yyyy - h:mm a',
    ).format(DateTime.now());

    final healthyCount = products.where((p) => p.stock > 5).length;
    final lowCount = products.where((p) => p.stock > 0 && p.stock <= 5).length;
    final outCount = products.where((p) => p.stock <= 0).length;
    final totalUnits = products.fold<double>(0.0, (sum, p) => sum + p.stock);
    final totalRetailValue = products.fold<double>(
      0.0,
      (sum, p) => sum + p.stockRetailValue,
    );
    final hasCostData = products.any((p) => p.costPrice != null);
    final totalCostValue = products.fold<double>(
      0.0,
      (sum, p) => sum + (p.stockCostValue ?? 0.0),
    );
    final totalPotentialProfit = products.fold<double>(
      0.0,
      (sum, p) => sum + (p.potentialStockProfit ?? 0.0),
    );

    final navyColor = PdfColor.fromHex('#131D2E');
    final orangeColor = PdfColor.fromHex('#F97316');
    final tealColor = PdfColor.fromHex('#0D9488');
    final amberColor = PdfColor.fromHex('#D97706');
    final roseColor = PdfColor.fromHex('#E11D48');
    final borderColor = PdfColor.fromHex('#E2E8F0');
    final mutedColor = PdfColor.fromHex('#64748B');
    final softBg = PdfColor.fromHex('#F8FAFC');

    final lowerFilter = filterLabel.toLowerCase();
    final badgeColor = lowerFilter.contains('out')
        ? roseColor
        : (lowerFilter.contains('low')
              ? amberColor
              : (lowerFilter.contains('healthy') ? tealColor : orangeColor));

    String formatMoney(double value) => '$currency${moneyFmt.format(value)}';
    String formatSignedMoney(double value) =>
        '${value < 0 ? '-' : '+'}$currency${moneyFmt.format(value.abs())}';

    final tableHeaders = hasCostData
        ? <String>[
            '#',
            'Product',
            'Category',
            'Cost',
            'Selling',
            'Profit',
            'Stock',
            'Status',
          ]
        : <String>[
            '#',
            'Product',
            'Category',
            'Price',
            'Stock',
            'Value',
            'Status',
          ];

    final tableRows = <List<String>>[];
    for (int i = 0; i < products.length; i++) {
      final p = products[i];
      final cleanName = _clean(p.name);
      final nameWithVariants = p.variants.isNotEmpty
          ? '$cleanName (${p.variants.length} var)'
          : cleanName;
      final cleanCat = (p.category != null && p.category!.trim().isNotEmpty)
          ? _clean(p.category!)
          : '-';
      final status = p.stock <= 0
          ? 'Out of stock'
          : (p.stock <= 5 ? 'Low Stock' : 'Healthy');

      if (hasCostData) {
        tableRows.add([
          '${i + 1}',
          nameWithVariants,
          cleanCat,
          p.costPrice != null ? formatMoney(p.costPrice!) : '-',
          formatMoney(p.price),
          p.unitProfit != null ? formatSignedMoney(p.unitProfit!) : '-',
          p.formattedStock,
          status,
        ]);
      } else {
        tableRows.add([
          '${i + 1}',
          nameWithVariants,
          cleanCat,
          formatMoney(p.price),
          p.formattedStock,
          formatMoney(p.stockRetailValue),
          status,
        ]);
      }
    }

    final columnWidths = hasCostData
        ? <int, pw.TableColumnWidth>{
            0: const pw.FixedColumnWidth(24),
            1: const pw.FlexColumnWidth(2.4),
            2: const pw.FlexColumnWidth(1.3),
            3: const pw.FlexColumnWidth(1.1),
            4: const pw.FlexColumnWidth(1.1),
            5: const pw.FlexColumnWidth(1.1),
            6: const pw.FlexColumnWidth(1.1),
            7: const pw.FlexColumnWidth(1.15),
          }
        : <int, pw.TableColumnWidth>{
            0: const pw.FixedColumnWidth(26),
            1: const pw.FlexColumnWidth(2.7),
            2: const pw.FlexColumnWidth(1.4),
            3: const pw.FlexColumnWidth(1.2),
            4: const pw.FlexColumnWidth(1.2),
            5: const pw.FlexColumnWidth(1.3),
            6: const pw.FlexColumnWidth(1.2),
          };

    final cellAlignments = hasCostData
        ? <int, pw.Alignment>{
            0: pw.Alignment.center,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.centerRight,
            7: pw.Alignment.center,
          }
        : <int, pw.Alignment>{
            0: pw.Alignment.center,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.center,
          };

    pw.Widget buildSummaryBox({
      required String label,
      required String value,
      PdfColor? valueColor,
      String? subtext,
    }) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: pw.BoxDecoration(
            color: softBg,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            border: pw.Border.all(color: borderColor, width: 0.8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: mutedColor,
                  letterSpacing: 0.4,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 12.5,
                  fontWeight: pw.FontWeight.bold,
                  color: valueColor ?? navyColor,
                ),
              ),
              if (subtext != null) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  subtext,
                  style: pw.TextStyle(fontSize: 7.5, color: mutedColor),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final cleanStore = _clean(storeName).isNotEmpty
        ? _clean(storeName)
        : 'TindaKo POS';
    final cleanAddress = _clean(storeAddress);
    final cleanPhone = _clean(storePhone);
    final cleanCategory = (categoryLabel != null &&
            categoryLabel.trim().isNotEmpty &&
            categoryLabel.trim() != 'All')
        ? _clean(categoryLabel)
        : null;

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
        fontFallback: fontFallbackList,
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 26, 26, 30),
        footer: (pw.Context context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 12),
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: borderColor, width: 0.7),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '$cleanStore - Inventory Report (${_clean(filterLabel)})',
                style: pw.TextStyle(fontSize: 8.5, color: mutedColor),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 8.5, color: mutedColor),
              ),
            ],
          ),
        ),
        build: (pw.Context context) => [
          // Header
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      cleanStore.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: navyColor,
                      ),
                    ),
                    if (cleanAddress.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        cleanAddress,
                        style: pw.TextStyle(fontSize: 9.5, color: mutedColor),
                      ),
                    ],
                    if (cleanPhone.isNotEmpty) ...[
                      pw.SizedBox(height: 1),
                      pw.Text(
                        cleanPhone,
                        style: pw.TextStyle(fontSize: 9.5, color: mutedColor),
                      ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: pw.BoxDecoration(
                      color: badgeColor,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                    ),
                    child: pw.Text(
                      'INVENTORY (${_clean(filterLabel).toUpperCase()})',
                      style: pw.TextStyle(
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  if (cleanCategory != null)
                    pw.Text(
                      'Category: $cleanCategory',
                      style: pw.TextStyle(
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        color: navyColor,
                      ),
                    ),
                  pw.Text(
                    'Sorted by: ${_clean(sortLabel)}',
                    style: pw.TextStyle(fontSize: 8.5, color: mutedColor),
                  ),
                  pw.Text(
                    'Generated: $dateGenerated',
                    style: pw.TextStyle(fontSize: 8.5, color: mutedColor),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Divider(color: borderColor, thickness: 1),
          pw.SizedBox(height: 12),

          // Summary KPI Strip
          pw.Row(
            children: [
              buildSummaryBox(
                label: 'Products',
                value: '${products.length}',
                subtext: '${formatQuantity(totalUnits)} total units',
              ),
              pw.SizedBox(width: 8),
              buildSummaryBox(
                label: 'Retail Value',
                value: formatMoney(totalRetailValue),
                valueColor: orangeColor,
              ),
              if (hasCostData) ...[
                pw.SizedBox(width: 8),
                buildSummaryBox(
                  label: 'Stock Cost',
                  value: formatMoney(totalCostValue),
                ),
                pw.SizedBox(width: 8),
                buildSummaryBox(
                  label: 'Est. Profit',
                  value: formatSignedMoney(totalPotentialProfit),
                  valueColor: totalPotentialProfit < 0 ? roseColor : tealColor,
                ),
              ],
            ],
          ),
          pw.SizedBox(height: 14),

          // Inventory Products Table
          if (tableRows.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(24),
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                color: softBg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: borderColor),
              ),
              child: pw.Text(
                'No products match this inventory filter.',
                style: pw.TextStyle(fontSize: 11, color: mutedColor),
              ),
            )
          else
            pw.TableHelper.fromTextArray(
              context: context,
              headers: tableHeaders,
              data: tableRows,
              columnWidths: columnWidths,
              headerStyle: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: navyColor),
              headerAlignment: pw.Alignment.centerLeft,
              headerAlignments: cellAlignments,
              cellStyle: const pw.TextStyle(fontSize: 8.5),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 5,
              ),
              cellAlignments: cellAlignments,
              oddRowDecoration: pw.BoxDecoration(color: softBg),
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(
                  color: borderColor,
                  width: 0.5,
                ),
                bottom: pw.BorderSide(color: borderColor, width: 0.8),
              ),
            ),

          if (tableRows.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: pw.BoxDecoration(
                color: softBg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: borderColor, width: 0.8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'STOCK HEALTH: $healthyCount Healthy | $lowCount Low | $outCount Out',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: navyColor,
                    ),
                  ),
                  pw.Text(
                    'Total Retail: ${formatMoney(totalRetailValue)}',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: orangeColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  /// Opens the native print / PDF preview dialog for an Inventory report.
  static Future<void> generateInventoryReport({
    required List<Product> products,
    required String filterLabel,
    required String sortLabel,
    String? categoryLabel,
    required String storeName,
    required String storeAddress,
    String? storePhone,
    String? fileName,
  }) async {
    final safeName = fileName ??
        'inventory_${filterLabel.toLowerCase().replaceAll(' ', '_')}.pdf';
    await Printing.layoutPdf(
      name: safeName,
      format: PdfPageFormat.a4,
      onLayout: (PdfPageFormat format) => buildInventoryReportPdfBytes(
        products: products,
        filterLabel: filterLabel,
        sortLabel: sortLabel,
        categoryLabel: categoryLabel,
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
      ),
    );
  }

  /// Saves the Inventory PDF via the OS save dialog on desktop, or shares it
  /// via the native share sheet on mobile/web.
  static Future<String?> saveOrShareInventoryReport({
    required List<Product> products,
    required String filterLabel,
    required String sortLabel,
    String? categoryLabel,
    required String storeName,
    required String storeAddress,
    String? storePhone,
    String? fileName,
  }) async {
    final safeName = fileName ??
        'inventory_${filterLabel.toLowerCase().replaceAll(' ', '_')}.pdf';
    final bytes = await buildInventoryReportPdfBytes(
      products: products,
      filterLabel: filterLabel,
      sortLabel: sortLabel,
      categoryLabel: categoryLabel,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
    );

    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (isDesktop) {
      final selectedPath = await FilePicker.saveFile(
        dialogTitle: 'Save Inventory PDF Report',
        fileName: safeName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (selectedPath == null || selectedPath.trim().isEmpty) return null;
      final finalPath = selectedPath.toLowerCase().endsWith('.pdf')
          ? selectedPath
          : '$selectedPath.pdf';
      await File(finalPath).writeAsBytes(bytes, flush: true);
      return finalPath;
    }

    await Printing.sharePdf(bytes: bytes, filename: safeName);
    return 'shared';
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
