import 'dart:math' as math;
import 'package:barcode/barcode.dart' as bc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_theme.dart';
import '../models/transaction.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/pdf_service.dart';
import 'store_image_view.dart';

/// Shows the authentic in-app cash receipt dialog
Future<void> showReceiptDialog(
  BuildContext context, {
  required SaleTransaction transaction,
  required List<Map<String, dynamic>> items,
  User? user,
  String? customerName,
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
      customerName: customerName,
      receiptFooterNote: settings.receiptFooterNote,
      initialPaperSize: settings.receiptPaperSize,
      businessPhotoPath: settings.businessPhotoPath.isNotEmpty
          ? settings.businessPhotoPath
          : authUser?.imagePath,
    ),
  );
}

class ReceiptDialog extends StatefulWidget {
  final SaleTransaction transaction;
  final List<Map<String, dynamic>> items;
  final User? user;
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final String? customerName;
  final String? businessPhotoPath;
  final String? receiptFooterNote;
  final String initialPaperSize;

  const ReceiptDialog({
    super.key,
    required this.transaction,
    required this.items,
    this.user,
    required this.storeName,
    required this.storeAddress,
    required this.storePhone,
    this.customerName,
    this.businessPhotoPath,
    this.receiptFooterNote,
    this.initialPaperSize = '58mm',
  });

  @override
  State<ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<ReceiptDialog> {
  late String _paperSize;

  @override
  void initState() {
    super.initState();
    _paperSize = widget.initialPaperSize;
  }

  void _setPaperSize(String size) {
    if (_paperSize == size) return;
    HapticFeedback.selectionClick();
    setState(() {
      _paperSize = size;
    });
    context.read<SettingsProvider>().setReceiptPaperSize(size);
  }

  void _shareReceipt() {
    final dateStr = DateFormat('MM-dd-yyyy hh:mm a').format(widget.transaction.date);
    final subtotalAmount = widget.transaction.totalAmount + widget.transaction.discount;
    final buffer = StringBuffer();
    final is58 = _paperSize == '58mm';
    final lineSep = is58
        ? '--------------------------------'
        : '========================================';
    final doubleSep = is58
        ? '================================'
        : '========================================';

    buffer.writeln(doubleSep);
    buffer.writeln(
      widget.storeName.trim().isNotEmpty
          ? widget.storeName.trim().toUpperCase()
          : 'TINDAKO STORE',
    );
    buffer.writeln('OFFICIAL RECEIPT');
    if (widget.storeAddress.trim().isNotEmpty) {
      buffer.writeln('Address: ${widget.storeAddress.trim()}');
    }
    final phone = widget.storePhone.trim().isNotEmpty
        ? widget.storePhone.trim()
        : '09XX XXX XXXX';
    buffer.writeln('Tel: $phone');
    buffer.writeln(lineSep);
    buffer.writeln('Receipt #: ${widget.transaction.id ?? 0}');
    buffer.writeln('Date: $dateStr');
    if (widget.user != null && widget.user!.fullName.trim().isNotEmpty) {
      buffer.writeln('Cashier: ${widget.user!.fullName.trim()}');
    }
    if (widget.customerName != null && widget.customerName!.trim().isNotEmpty) {
      buffer.writeln('Customer: ${widget.customerName!.trim()}');
    }
    buffer.writeln(lineSep);
    buffer.writeln('ITEM / QTY                       AMOUNT');
    buffer.writeln(lineSep);

    for (final item in widget.items) {
      final name = (item['product_name'] ?? 'Item').toString();
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      final subtotal = ((item['subtotal'] as num?) ?? 0.0).toDouble();
      final unitPrice = qty > 0 ? (subtotal / qty) : subtotal;

      buffer.writeln(name);
      buffer.writeln('  $qty x P${unitPrice.toStringAsFixed(2).padLeft(7)}    P${subtotal.toStringAsFixed(2).padLeft(9)}');
    }

    buffer.writeln(lineSep);
    buffer.writeln('Sub-total:            P${subtotalAmount.toStringAsFixed(2).padLeft(9)}');
    if (widget.transaction.discount > 0) {
      buffer.writeln('Discount:            -P${widget.transaction.discount.toStringAsFixed(2).padLeft(9)}');
    }
    buffer.writeln(doubleSep);
    buffer.writeln('TOTAL DUE:            P${widget.transaction.totalAmount.toStringAsFixed(2).padLeft(9)}');
    buffer.writeln(doubleSep);

    final isGcash = widget.transaction.paymentMethod.toLowerCase() == 'gcash';
    final isDebt = widget.transaction.paymentMethod.toLowerCase() == 'pending' ||
        widget.transaction.paymentMethod.toLowerCase() == 'debt';

    if (isGcash) {
      buffer.writeln('Payment: GCASH        P${widget.transaction.totalAmount.toStringAsFixed(2).padLeft(9)}');
      buffer.writeln('Status: COMPLETED');
    } else if (isDebt) {
      final bal = (widget.transaction.totalAmount - widget.transaction.cashReceived)
          .clamp(0.0, widget.transaction.totalAmount);
      buffer.writeln('Deposit / Paid:       P${widget.transaction.cashReceived.toStringAsFixed(2).padLeft(9)}');
      buffer.writeln('Remaining Balance:    P${bal.toStringAsFixed(2).padLeft(9)}');
    } else {
      buffer.writeln('Cash Tendered:        P${widget.transaction.cashReceived.toStringAsFixed(2).padLeft(9)}');
      buffer.writeln('Change:               P${widget.transaction.change.toStringAsFixed(2).padLeft(9)}');
    }

    buffer.writeln(lineSep);
    buffer.writeln(
      widget.receiptFooterNote?.trim().isNotEmpty == true
          ? widget.receiptFooterNote!.trim().toUpperCase()
          : 'THANK YOU FOR YOUR PURCHASE!',
    );
    buffer.writeln(doubleSep);

    SharePlus.instance.share(
      ShareParams(
        text: buffer.toString(),
        subject: 'Receipt #${widget.transaction.id ?? 0}',
      ),
    );
  }

  void _printReceipt() {
    HapticFeedback.lightImpact();
    PdfService.generateAndPrintReceipt(
      transaction: widget.transaction,
      items: widget.items,
      user: widget.user,
      storeName: widget.storeName,
      storeAddress: widget.storeAddress,
      storePhone: widget.storePhone,
      customerName: widget.customerName,
      businessPhotoPath: widget.businessPhotoPath,
      receiptFooterNote: widget.receiptFooterNote,
      paperSize: _paperSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM dd, yyyy').format(widget.transaction.date);
    final timeStr = DateFormat('hh:mm a').format(widget.transaction.date);
    final phone = widget.storePhone.trim().isNotEmpty
        ? widget.storePhone.trim()
        : '09XX XXX XXXX';
    final subtotalAmount = widget.transaction.totalAmount + widget.transaction.discount;
    final isGcash = widget.transaction.paymentMethod.toLowerCase() == 'gcash';
    final isDebt = widget.transaction.paymentMethod.toLowerCase() == 'pending' ||
        widget.transaction.paymentMethod.toLowerCase() == 'debt';
    final is58 = _paperSize == '58mm';

    final monoStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: is58 ? 11 : 12,
      color: const Color(0xFF334155),
      height: 1.35,
      fontFeatures: AppTheme.tabularFigures,
    );
    final monoMuted = TextStyle(
      fontFamily: 'monospace',
      fontSize: is58 ? 10 : 11,
      color: const Color(0xFF64748B),
      height: 1.3,
      fontFeatures: AppTheme.tabularFigures,
    );
    final monoBold = TextStyle(
      fontFamily: 'monospace',
      fontSize: is58 ? 11 : 12,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF0F172A),
      height: 1.35,
      fontFeatures: AppTheme.tabularFigures,
    );
    final monoHeader = TextStyle(
      fontFamily: 'monospace',
      fontSize: is58 ? 14 : 16,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.2,
      color: const Color(0xFF0F172A),
    );
    final monoTotal = TextStyle(
      fontFamily: 'monospace',
      fontSize: is58 ? 15 : 17,
      fontWeight: FontWeight.w900,
      color: const Color(0xFF0F172A),
      fontFeatures: AppTheme.tabularFigures,
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: is58 ? 336 : 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Top Bar: Header Pill & Thermal Width Switcher ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryDark.withValues(alpha: 0.94),
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
                            size: 15,
                            color: AppTheme.accentTeal,
                          ),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Official Cash Receipt',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Paper Size Toggle Pill
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryDark.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.borderDark),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildPaperToggle('58mm', '58mm'),
                        _buildPaperToggle('80mm', '80mm'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

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
                    padding: EdgeInsets.fromLTRB(
                      is58 ? 16 : 22,
                      20,
                      is58 ? 16 : 22,
                      20,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Store Header & Logo
                        if (widget.businessPhotoPath != null &&
                            widget.businessPhotoPath!.isNotEmpty) ...[
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: StoreImageView(
                                imagePath: widget.businessPhotoPath,
                                width: is58 ? 44 : 52,
                                height: is58 ? 44 : 52,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                        Center(
                          child: Text(
                            widget.storeName.trim().isNotEmpty
                                ? widget.storeName.trim().toUpperCase()
                                : 'TINDAKO STORE',
                            style: monoHeader,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Center(
                          child: Text('OFFICIAL RECEIPT', style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                            letterSpacing: 1.0,
                          )),
                        ),
                        if (widget.storeAddress.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Center(
                            child: Text(
                              widget.storeAddress.trim(),
                              style: monoMuted,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Center(
                          child: Text('Tel: $phone', style: monoMuted),
                        ),

                        const SizedBox(height: 10),
                        const DashedDivider(),
                        const SizedBox(height: 8),

                        // Metadata Rows
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Receipt #${widget.transaction.id ?? 0}',
                              style: monoBold,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDebt
                                    ? AppTheme.accentAmber.withValues(alpha: 0.18)
                                    : (isGcash
                                        ? AppTheme.accentTeal.withValues(alpha: 0.18)
                                        : const Color(0xFFE2E8F0)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isGcash
                                    ? 'GCASH'
                                    : (isDebt ? 'STORE CREDIT' : 'CASH'),
                                style: monoBold.copyWith(
                                  fontSize: 10,
                                  color: isDebt
                                      ? AppTheme.accentAmber
                                      : (isGcash ? AppTheme.accentTeal : null),
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
                        if (widget.user != null &&
                            widget.user!.fullName.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Cashier', style: monoMuted),
                              Flexible(
                                child: Text(
                                  widget.user!.fullName.trim(),
                                  style: monoMuted,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (isDebt &&
                            widget.customerName != null &&
                            widget.customerName!.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Customer', style: monoBold),
                              Flexible(
                                child: Text(
                                  widget.customerName!.trim(),
                                  style: monoBold,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 8),
                        const DashedDivider(),
                        const SizedBox(height: 6),

                        // Column Header
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('ITEM / QTY', style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475569),
                            )),
                            Text('AMOUNT', style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475569),
                            )),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const DashedDivider(),
                        const SizedBox(height: 6),

                        // Itemized List (Matching Authentic Layout)
                        ...widget.items.map((item) {
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
                                      Text(name, style: monoBold),
                                      if (qty > 1)
                                        Text(
                                          '$qty x ₱${unitPrice.toStringAsFixed(2)}',
                                          style: monoMuted,
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
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

                        // Subtotal & Discount
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Sub-total', style: monoStyle),
                            Text(
                              '₱${subtotalAmount.toStringAsFixed(2)}',
                              style: monoStyle,
                            ),
                          ],
                        ),
                        if (widget.transaction.discount > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Discount', style: monoStyle),
                              Text(
                                '-₱${widget.transaction.discount.toStringAsFixed(2)}',
                                style: monoStyle,
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),

                        // Prominent Total Box
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: const BoxDecoration(
                            border: Border.symmetric(
                              horizontal: BorderSide(
                                color: Color(0xFF0F172A),
                                width: 1.2,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('TOTAL', style: monoTotal),
                              Text(
                                '₱${widget.transaction.totalAmount.toStringAsFixed(2)}',
                                style: monoTotal,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Tendered, Change, or Credit Balance
                        if (isGcash) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('GCash Paid', style: monoStyle),
                              Text(
                                '₱${widget.transaction.totalAmount.toStringAsFixed(2)}',
                                style: monoBold,
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Payment Status', style: monoStyle),
                              Text('COMPLETED', style: monoBold),
                            ],
                          ),
                        ] else if (isDebt) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Deposit / Paid', style: monoStyle),
                              Text(
                                '₱${widget.transaction.cashReceived.toStringAsFixed(2)}',
                                style: monoStyle,
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Remaining Balance', style: monoBold),
                              Text(
                                '₱${(widget.transaction.totalAmount - widget.transaction.cashReceived).clamp(0.0, widget.transaction.totalAmount).toStringAsFixed(2)}',
                                style: monoBold.copyWith(
                                  color: AppTheme.accentAmber,
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Cash Tendered', style: monoStyle),
                              Text(
                                '₱${widget.transaction.cashReceived.toStringAsFixed(2)}',
                                style: monoStyle,
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Change', style: monoBold),
                              Text(
                                '₱${widget.transaction.change.toStringAsFixed(2)}',
                                style: monoBold,
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            widget.receiptFooterNote?.trim().isNotEmpty == true
                                ? widget.receiptFooterNote!.trim().toUpperCase()
                                : 'THANK YOU FOR YOUR PURCHASE!',
                            style: monoBold.copyWith(
                              letterSpacing: 0.8,
                              fontSize: is58 ? 10 : 11,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Barcode
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: is58 ? 150 : 180,
                                height: 38,
                                child: CustomPaint(
                                  painter: BarcodePainter(
                                    data: 'ORDER-${widget.transaction.id ?? 0}',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ORDER #${widget.transaction.id ?? 0}',
                                style: monoMuted.copyWith(
                                  fontSize: 10,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w600,
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

              const SizedBox(height: 12),

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
                        minimumSize: const Size(46, 46),
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
                      tooltip: 'Print Thermal Receipt ($_paperSize)',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(46, 46),
                        backgroundColor: AppTheme.accentTeal.withValues(alpha: 0.2),
                        foregroundColor: AppTheme.accentTeal,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 46,
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
                              fontSize: 14,
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

  Widget _buildPaperToggle(String value, String label) {
    final isSelected = _paperSize == value;
    return GestureDetector(
      onTap: () => _setPaperSize(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentOrange : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.white70,
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
