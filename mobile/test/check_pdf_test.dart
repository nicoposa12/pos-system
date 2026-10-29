// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  test('verify receipt design with courier', () async {
    final pdf = pw.Document();
    final fontMono = pw.Font.courier();
    final fontMonoBold = pw.Font.courierBold();

    final pageFormat = PdfPageFormat(
      72 * PdfPageFormat.mm,
      double.infinity,
      marginLeft: 6 * PdfPageFormat.mm,
      marginRight: 6 * PdfPageFormat.mm,
      marginTop: 8 * PdfPageFormat.mm,
      marginBottom: 8 * PdfPageFormat.mm,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) {
          final regular = pw.TextStyle(font: fontMono, fontSize: 9);
          final bold = pw.TextStyle(font: fontMonoBold, fontSize: 9);
          final titleStyle = pw.TextStyle(font: fontMonoBold, fontSize: 13);
          final totalStyle = pw.TextStyle(font: fontMonoBold, fontSize: 13);

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Header
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text('CASH RECEIPT', style: titleStyle),
                    pw.SizedBox(height: 3),
                    pw.Text('MINI-STORE', style: bold),
                    pw.Text('Address: Your Address Here', style: regular, textAlign: pw.TextAlign.center),
                    pw.Text('Tel: 123-456-7890', style: regular),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.8),
              pw.SizedBox(height: 2),

              // Date & Time row
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Date: 10-29-2026', style: regular),
                  pw.Text('04:04', style: regular),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.8),
              pw.SizedBox(height: 4),

              // Items
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(child: pw.Text('Mega Sardines x4', style: regular)),
                  pw.Text('100.00', style: regular),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(child: pw.Text('Coke x2', style: regular)),
                  pw.Text('40.00', style: regular),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(child: pw.Text('Super Crunch x2', style: regular)),
                  pw.Text('30.00', style: regular),
                ],
              ),

              pw.SizedBox(height: 6),
              pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.8),
              pw.SizedBox(height: 4),

              // Total
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total', style: totalStyle),
                  pw.Text('170.00', style: totalStyle),
                ],
              ),
              pw.SizedBox(height: 6),

              // Breakdown
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Sub-total', style: regular),
                  pw.Text('170.00', style: regular),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Cash Received', style: regular),
                  pw.Text('200.00', style: regular),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Change', style: regular),
                  pw.Text('30.00', style: regular),
                ],
              ),

              pw.SizedBox(height: 14),
              pw.Center(
                child: pw.Text('THANK YOU', style: pw.TextStyle(font: fontMonoBold, fontSize: 12, letterSpacing: 1.5)),
              ),
              pw.SizedBox(height: 8),

              // Barcode
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: 'RCPT-2',
                  width: 140,
                  height: 36,
                  drawText: false,
                ),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    print('PDF generated successfully, bytes: ${bytes.length}');
  });
}
