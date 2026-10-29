import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../models/user.dart';

class PdfService {
  static Future<void> generateAndPrintReceipt({
    required SaleTransaction transaction,
    required List<Map<String, dynamic>> items,
    required User? user,
    required String storeName,
    required String storeAddress,
    String? storePhone,
  }) async {
    final fontMono = pw.Font.courier();
    final fontMonoBold = pw.Font.courierBold();

    final dateStr = DateFormat('MM-dd-yyyy').format(transaction.date);
    final timeStr = DateFormat('HH:mm').format(transaction.date);

    await Printing.layoutPdf(
      name: 'receipt_${transaction.id}.pdf',
      format: PdfPageFormat.roll80,
      onLayout: (PdfPageFormat format) async {
        final pdf = pw.Document();

        final isRoll =
            format.height == double.infinity ||
            format.width <= 100 * PdfPageFormat.mm;

        final pageFormat = isRoll
            ? PdfPageFormat(
                format.width > 0 ? format.width : PdfPageFormat.roll80.width,
                double.infinity,
                marginLeft: 10,
                marginRight: 10,
                marginTop: 12,
                marginBottom: 12,
              )
            : format.copyWith(
                marginLeft: 24,
                marginRight: 24,
                marginTop: 28,
                marginBottom: 28,
              );

        final availableWidth = pageFormat.availableWidth;
        // Base width for thermal roll is ~200 pt.
        // Scale font and widgets dynamically up to 2.4x for large sheets (Letter, A4, Legal)
        final scale = (availableWidth / 200.0).clamp(0.7, 2.4);

        final regular = pw.TextStyle(font: fontMono, fontSize: 9 * scale);
        final bold = pw.TextStyle(font: fontMonoBold, fontSize: 9 * scale);
        final titleStyle = pw.TextStyle(
          font: fontMonoBold,
          fontSize: 13 * scale,
        );
        final totalStyle = pw.TextStyle(
          font: fontMonoBold,
          fontSize: 13 * scale,
        );

        final spacing = 4.0 * scale;
        final barcodeW = (140.0 * scale).clamp(100.0, availableWidth * 0.75);
        final barcodeH = (36.0 * scale).clamp(28.0, 85.0);
        final dividerThick = (0.8 * scale).clamp(0.6, 2.0);

        final phone = (storePhone != null && storePhone.trim().isNotEmpty)
            ? storePhone.trim()
            : '09XX XXX XXXX';

        pdf.addPage(
          pw.Page(
            pageFormat: pageFormat,
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // Centered Header
                  pw.Center(
                    child: pw.Column(
                      children: [
                        pw.Text('CASH RECEIPT', style: titleStyle),
                        pw.SizedBox(height: spacing * 0.6),
                        if (storeName.trim().isNotEmpty)
                          pw.Text(storeName.trim().toUpperCase(), style: bold),
                        if (storeAddress.trim().isNotEmpty)
                          pw.Text(
                            'Address: ${storeAddress.trim()}',
                            style: regular,
                            textAlign: pw.TextAlign.center,
                          ),
                        pw.Text('Tel: $phone', style: regular),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: spacing * 1.2),
                  pw.Divider(
                    borderStyle: pw.BorderStyle.dashed,
                    thickness: dividerThick,
                  ),
                  pw.SizedBox(height: spacing * 0.5),

                  // Order # and Date/Time
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Order #${transaction.id ?? 0}', style: bold),
                      pw.Text('$dateStr  $timeStr', style: regular),
                    ],
                  ),
                  pw.SizedBox(height: spacing * 0.5),
                  pw.Divider(
                    borderStyle: pw.BorderStyle.dashed,
                    thickness: dividerThick,
                  ),
                  pw.SizedBox(height: spacing * 0.8),

                  // Itemized List
                  ...items.map((item) {
                    final name = item['product_name'] ?? 'Item';
                    final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                    final subtotal = ((item['subtotal'] as num?) ?? 0.0)
                        .toDouble();
                    final displayName = qty > 1 ? '$name x$qty' : name;

                    return pw.Padding(
                      padding: pw.EdgeInsets.symmetric(vertical: spacing * 0.4),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            child: pw.Text(displayName, style: regular),
                          ),
                          pw.SizedBox(width: spacing * 2),
                          pw.Text(subtotal.toStringAsFixed(2), style: regular),
                        ],
                      ),
                    );
                  }),

                  pw.SizedBox(height: spacing * 1.2),
                  pw.Divider(
                    borderStyle: pw.BorderStyle.dashed,
                    thickness: dividerThick,
                  ),
                  pw.SizedBox(height: spacing * 0.8),

                  // Prominent Total
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Total', style: totalStyle),
                      pw.Text(
                        transaction.totalAmount.toStringAsFixed(2),
                        style: totalStyle,
                      ),
                    ],
                  ),
                  pw.SizedBox(height: spacing * 1.2),

                  // Sub-total & Breakdown
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Sub-total', style: regular),
                      pw.Text(
                        (transaction.totalAmount + transaction.discount)
                            .toStringAsFixed(2),
                        style: regular,
                      ),
                    ],
                  ),
                  if (transaction.discount > 0) ...[
                    pw.SizedBox(height: spacing * 0.5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Discount', style: regular),
                        pw.Text(
                          '-${transaction.discount.toStringAsFixed(2)}',
                          style: regular,
                        ),
                      ],
                    ),
                  ],
                  pw.SizedBox(height: spacing * 0.5),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        transaction.paymentMethod == 'gcash'
                            ? 'GCash'
                            : 'Cash Received',
                        style: regular,
                      ),
                      pw.Text(
                        (transaction.paymentMethod == 'gcash'
                                ? transaction.totalAmount
                                : transaction.cashReceived)
                            .toStringAsFixed(2),
                        style: regular,
                      ),
                    ],
                  ),
                  pw.SizedBox(height: spacing * 0.5),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Change', style: regular),
                      pw.Text(
                        transaction.change.toStringAsFixed(2),
                        style: regular,
                      ),
                    ],
                  ),

                  // Footer & Barcode
                  pw.SizedBox(height: spacing * 2.2),
                  pw.Center(
                    child: pw.Text(
                      'THANK YOU',
                      style: pw.TextStyle(
                        font: fontMonoBold,
                        fontSize: 12 * scale,
                        letterSpacing: 1.5 * scale,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: spacing * 1.4),
                  pw.Center(
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.code128(),
                      data: 'ORDER-${transaction.id ?? 0}',
                      width: barcodeW,
                      height: barcodeH,
                      drawText: true,
                      textStyle: pw.TextStyle(
                        font: fontMonoBold,
                        fontSize: 8 * scale,
                        letterSpacing: 1.2 * scale,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );

        return pdf.save();
      },
    );
  }

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
                      storeName.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      storeAddress,
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
                      periodLabel,
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
