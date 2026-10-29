import 'dart:io';
import 'dart:math' as math;
import 'package:barcode/barcode.dart' as bc;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_theme.dart';
import '../models/transaction.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/pdf_service.dart';

/// Shows the authentic in-app cash receipt dialog
Future<void> showReceiptDialog(
  BuildContext context, {
  required SaleTransaction transaction,
  required List<Map<String, dynamic>> items,
  User? user,
}) {
  final settings = context.read<SettingsProvider>();
  final authUser = user ?? context.read<AuthProvider>().currentUser;

  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (ctx) => ReceiptDialog(
      transaction: transaction,
      items: items,
      user: authUser,
      storeName: settings.storeName,
      storeAddress: settings.storeAddress,
      storePhone: settings.storePhone,
      businessPhotoPath: settings.businessPhotoPath,
    ),
  );
}

class ReceiptDialog extends StatelessWidget {
  final SaleTransaction transaction;
  final List<Map<String, dynamic>> items;
  final User? user;
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final String? businessPhotoPath;

  const ReceiptDialog({
    super.key,
    required this.transaction,
    required this.items,
    this.user,
    required this.storeName,
    required this.storeAddress,
    required this.storePhone,
    this.businessPhotoPath,
  });

  void _shareReceipt() {
    final dateStr = DateFormat('MM-dd-yyyy HH:mm').format(transaction.date);
    final subtotalAmount = transaction.totalAmount + transaction.discount;
    final buffer = StringBuffer();
    buffer.writeln('==============================');
    buffer.writeln('         CASH RECEIPT         ');
    if (storeName.trim().isNotEmpty) {
      buffer.writeln('     ${storeName.trim().toUpperCase()}');
    }
    if (storeAddress.trim().isNotEmpty) {
      buffer.writeln('  Address: ${storeAddress.trim()}');
    }
    final phone = storePhone.trim().isNotEmpty
        ? storePhone.trim()
        : '09XX XXX XXXX';
    buffer.writeln('  Tel: $phone');
    buffer.writeln('------------------------------');
    buffer.writeln('Order #: ${transaction.id ?? 0}');
    buffer.writeln('Date: $dateStr');
    if (user != null && user!.fullName.trim().isNotEmpty) {
      buffer.writeln('Cashier: ${user!.fullName.trim()}');
    }
    buffer.writeln('------------------------------');
    for (final item in items) {
      final name = item['product_name'] ?? 'Item';
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      final subtotal = ((item['subtotal'] as num?) ?? 0.0).toDouble();
      final displayName = qty > 1 ? '$name x$qty' : '$name';
      buffer.writeln(
        '${displayName.padRight(20)} ${subtotal.toStringAsFixed(2).padLeft(8)}',
      );
    }
    buffer.writeln('------------------------------');
    buffer.writeln(
      'Sub-total            ${subtotalAmount.toStringAsFixed(2).padLeft(8)}',
    );
    if (transaction.discount > 0) {
      buffer.writeln(
        'Discount            -${transaction.discount.toStringAsFixed(2).padLeft(8)}',
      );
    }
    buffer.writeln(
      'TOTAL                ${transaction.totalAmount.toStringAsFixed(2).padLeft(8)}',
    );
    final isGcash = transaction.paymentMethod.toLowerCase() == 'gcash';
    final isPending = transaction.paymentMethod.toLowerCase() == 'pending' ||
        transaction.paymentMethod.toLowerCase() == 'debt';
    final payMethod = isGcash
        ? 'GCash Paid'
        : (isPending ? 'Deposit / Paid' : 'Cash Received');
    final payAmount = isGcash
        ? transaction.totalAmount
        : transaction.cashReceived;
    buffer.writeln(
      '${payMethod.padRight(20)} ${payAmount.toStringAsFixed(2).padLeft(8)}',
    );
    if (isPending) {
      final bal = (transaction.totalAmount - transaction.cashReceived).clamp(0.0, transaction.totalAmount);
      buffer.writeln(
        '${'Balance Due'.padRight(20)} ${bal.toStringAsFixed(2).padLeft(8)}',
      );
    }
    buffer.writeln(
      'Change               ${transaction.change.toStringAsFixed(2).padLeft(8)}',
    );
    buffer.writeln('==============================');
    buffer.writeln('          THANK YOU           ');
    buffer.writeln('==============================');

    SharePlus.instance.share(
      ShareParams(
        text: buffer.toString(),
        subject: 'Receipt #${transaction.id}',
      ),
    );
  }

  void _printReceipt() {
    PdfService.generateAndPrintReceipt(
      transaction: transaction,
      items: items,
      user: user,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM dd, yyyy').format(transaction.date);
    final timeStr = DateFormat('hh:mm a').format(transaction.date);
    final phone = storePhone.trim().isNotEmpty
        ? storePhone.trim()
        : '09XX XXX XXXX';
    final subtotalAmount = transaction.totalAmount + transaction.discount;
    final isGcash = transaction.paymentMethod.toLowerCase() == 'gcash';
    final isPending = transaction.paymentMethod.toLowerCase() == 'pending' ||
        transaction.paymentMethod.toLowerCase() == 'debt';

    const monoStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      color: Color(0xFF334155),
      height: 1.4,
      fontFeatures: AppTheme.tabularFigures,
    );
    const monoMuted = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      color: Color(0xFF64748B),
      height: 1.35,
      fontFeatures: AppTheme.tabularFigures,
    );
    const monoBold = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: Color(0xFF0F172A),
      height: 1.4,
      fontFeatures: AppTheme.tabularFigures,
    );
    const monoHeader = TextStyle(
      fontFamily: 'monospace',
      fontSize: 15,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.6,
      color: Color(0xFF0F172A),
    );
    const monoTotal = TextStyle(
      fontFamily: 'monospace',
      fontSize: 16,
      fontWeight: FontWeight.w900,
      color: Color(0xFF0F172A),
      fontFeatures: AppTheme.tabularFigures,
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 368),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Top Confirmation Pill ──
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryDark.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppTheme.accentTeal.withValues(alpha: 0.45),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: AppTheme.accentTeal,
                    ),
                    SizedBox(width: 7),
                    Text(
                      'Official Cash Receipt',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Thermal Receipt Paper Slip ──
              Flexible(
                child: PhysicalShape(
                  clipper: const JaggedEdgeClipper(
                    toothWidth: 7.5,
                    toothHeight: 5.0,
                  ),
                  color: const Color(0xFFFFFDF9),
                  elevation: 16,
                  shadowColor: Colors.black.withValues(alpha: 0.45),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Store Header
                        if (businessPhotoPath != null &&
                            businessPhotoPath!.isNotEmpty &&
                            File(businessPhotoPath!).existsSync()) ...[
                          Center(
                            child: Container(
                              width: 52,
                              height: 52,
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                image: DecorationImage(
                                  image: FileImage(File(businessPhotoPath!)),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ],
                        Center(
                          child: Text(
                            storeName.trim().isNotEmpty
                                ? storeName.trim().toUpperCase()
                                : 'TINDAKO STORE',
                            style: monoHeader,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Center(
                          child: Text('OFFICIAL RECEIPT', style: monoMuted),
                        ),
                        if (storeAddress.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Center(
                            child: Text(
                              storeAddress.trim(),
                              style: monoMuted,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Center(
                          child: Text('Tel: $phone', style: monoMuted),
                        ),

                        const SizedBox(height: 12),
                        const DashedDivider(),
                        const SizedBox(height: 8),

                        // Metadata Rows
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Receipt #${transaction.id ?? 0}',
                              style: monoBold,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isPending
                                    ? AppTheme.accentAmber.withValues(alpha: 0.18)
                                    : const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isGcash
                                    ? 'GCASH'
                                    : (isPending ? 'PENDING' : 'CASH'),
                                style: monoBold.copyWith(
                                  fontSize: 10,
                                  color: isPending ? AppTheme.accentAmber : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(dateStr, style: monoMuted),
                            Text(timeStr, style: monoMuted),
                          ],
                        ),
                        if (user != null &&
                            user!.fullName.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Cashier', style: monoMuted),
                              Flexible(
                                child: Text(
                                  user!.fullName.trim(),
                                  style: monoMuted,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 8),
                        const DashedDivider(),
                        const SizedBox(height: 8),

                        // Column Header
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('ITEM / QTY', style: monoMuted),
                            Text('AMOUNT', style: monoMuted),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Itemized List
                        ...items.map((item) {
                          final name =
                              (item['product_name'] ?? 'Item').toString();
                          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                          final subtotal =
                              ((item['subtotal'] as num?) ?? 0.0).toDouble();
                          final unitPrice = qty > 0 ? subtotal / qty : subtotal;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3.5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: monoStyle),
                                      if (qty > 1)
                                        Text(
                                          '$qty x ₱${unitPrice.toStringAsFixed(2)}',
                                          style: monoMuted,
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '₱${subtotal.toStringAsFixed(2)}',
                                  style: monoBold,
                                ),
                              ],
                            ),
                          );
                        }),

                        const SizedBox(height: 8),
                        const DashedDivider(),
                        const SizedBox(height: 8),

                        // Subtotal & Discount BEFORE Total
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Sub-total', style: monoStyle),
                            Text(
                              '₱${subtotalAmount.toStringAsFixed(2)}',
                              style: monoStyle,
                            ),
                          ],
                        ),
                        if (transaction.discount > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Discount', style: monoStyle),
                              Text(
                                '-₱${transaction.discount.toStringAsFixed(2)}',
                                style: monoStyle,
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),

                        // Prominent Total
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: const BoxDecoration(
                            border: Border.symmetric(
                              horizontal: BorderSide(
                                color: Color(0xFFCBD5E1),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('TOTAL', style: monoTotal),
                              Text(
                                '₱${transaction.totalAmount.toStringAsFixed(2)}',
                                style: monoTotal,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Tendered & Change
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isGcash
                                  ? 'GCash Paid'
                                  : (isPending ? 'Deposit / Paid' : 'Cash Tendered'),
                              style: monoStyle,
                            ),
                            Text(
                              '₱${(isGcash ? transaction.totalAmount : transaction.cashReceived).toStringAsFixed(2)}',
                              style: monoStyle,
                            ),
                          ],
                        ),
                        if (isPending) ...[
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Pending Balance', style: monoBold),
                              Text(
                                '₱${(transaction.totalAmount - transaction.cashReceived).clamp(0.0, transaction.totalAmount).toStringAsFixed(2)}',
                                style: monoBold.copyWith(
                                  color: AppTheme.accentAmber,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Change', style: monoBold),
                            Text(
                              '₱${transaction.change.toStringAsFixed(2)}',
                              style: monoBold,
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            'THANK YOU FOR YOUR PURCHASE!',
                            style: monoBold.copyWith(
                              letterSpacing: 1.0,
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Barcode
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 184,
                                height: 40,
                                child: CustomPaint(
                                  painter: BarcodePainter(
                                    data: 'ORDER-${transaction.id ?? 0}',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ORDER #${transaction.id ?? 0}',
                                style: monoMuted.copyWith(
                                  fontSize: 10,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ── Floating Action Dock ──
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryDark.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.borderDark),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _shareReceipt,
                      icon: const Icon(Icons.share_outlined, size: 20),
                      tooltip: 'Share Receipt',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: AppTheme.cardDark,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _printReceipt,
                      icon: const Icon(Icons.print_outlined, size: 20),
                      tooltip: 'Print Receipt',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: AppTheme.cardDark,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.check_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Done',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              fontSize: 15,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentOrange,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws an authentic dashed line between receipt sections
class DashedDivider extends StatelessWidget {
  final double height;
  final Color color;

  const DashedDivider({
    super.key,
    this.height = 1.0,
    this.color = const Color(0xFF94A3B8),
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 4.0;
        const dashSpace = 3.0;
        final dashCount = (boxWidth / (dashWidth + dashSpace)).floor();
        if (dashCount <= 0) return const SizedBox.shrink();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: dashWidth,
              height: height,
              child: DecoratedBox(decoration: BoxDecoration(color: color)),
            );
          }),
        );
      },
    );
  }
}

/// Realistic jagged / torn paper edge at the top and bottom of the receipt
class JaggedEdgeClipper extends CustomClipper<Path> {
  final double toothWidth;
  final double toothHeight;

  const JaggedEdgeClipper({this.toothWidth = 7.0, this.toothHeight = 4.5});

  @override
  Path getClip(Size size) {
    final path = Path();
    // Top jagged teeth
    path.moveTo(0, toothHeight);
    double x = 0;
    bool up = false;
    while (x < size.width) {
      x += toothWidth;
      up = !up;
      path.lineTo(math.min(x, size.width), up ? 0 : toothHeight);
    }
    path.lineTo(size.width, size.height - toothHeight);

    // Bottom jagged teeth
    x = size.width;
    up = false;
    while (x > 0) {
      x -= toothWidth;
      up = !up;
      path.lineTo(math.max(x, 0), size.height - (up ? toothHeight : 0));
    }
    path.lineTo(0, toothHeight);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(JaggedEdgeClipper oldClipper) =>
      oldClipper.toothWidth != toothWidth ||
      oldClipper.toothHeight != toothHeight;
}

/// Renders a clean Code128-style barcode
class BarcodePainter extends CustomPainter {
  final String data;
  final Color color;

  BarcodePainter({required this.data, this.color = const Color(0xFF0F172A)});

  @override
  void paint(Canvas canvas, Size size) {
    final barcode = bc.Barcode.code128();
    final elements = barcode.make(data, width: size.width, height: size.height);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final elem in elements) {
      if (elem is bc.BarcodeBar && elem.black) {
        canvas.drawRect(
          Rect.fromLTWH(elem.left, elem.top, elem.width, elem.height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(BarcodePainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.color != color;
}
