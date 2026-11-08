import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../models/transaction.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/transaction_provider.dart';
import 'receipt_dialog.dart';

/// Parses an order/receipt barcode or text string.
/// Returns the numeric order ID if it matches receipt patterns like:
/// - "ORDER-19", "ORDER #19", "ORDER19", "order-19", "order 19"
/// - "TX-19", "RECEIPT-19", "REC-19"
/// - "#19"
/// Returns null if the barcode does not match an order pattern (e.g. standard product barcode).
int? parseOrderBarcode(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  // Case 1: Prefixed with ORDER, TX, RECEIPT, or REC
  final prefixMatch = RegExp(
    r'^(?:ORDER|TX|RECEIPT|REC)[-\s#:]*(\d+)$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (prefixMatch != null) {
    return int.tryParse(prefixMatch.group(1)!);
  }

  // Case 2: Starts with # followed by digits (e.g. #19)
  final hashMatch = RegExp(r'^#\s*(\d+)$').firstMatch(trimmed);
  if (hashMatch != null) {
    return int.tryParse(hashMatch.group(1)!);
  }

  return null;
}

/// Handles scanning an order receipt barcode.
/// If [rawBarcode] is an order barcode, looks up the transaction and opens the Order modal.
/// Returns true if the barcode was handled as an order barcode (preventing product-lookup fallback).
/// Returns false if the barcode is not an order barcode.
Future<bool> handleOrderBarcodeScan(
  BuildContext context,
  String rawBarcode, {
  bool showNotFoundMessage = true,
}) async {
  final orderId = parseOrderBarcode(rawBarcode);
  if (orderId == null) return false;

  final txProvider = context.read<TransactionProvider>();
  final transaction = await txProvider.findTransaction(orderId);

  if (!context.mounted) return true;

  if (transaction == null) {
    HapticFeedback.vibrate();
    if (showNotFoundMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Order #$orderId was not found in records'),
              ),
            ],
          ),
          backgroundColor: AppTheme.accentRose,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return true;
  }

  HapticFeedback.mediumImpact();
  await showOrderDetailsModal(context, transaction);
  return true;
}

/// Displays the authentic Order details bottom sheet with items, returns,
/// payment info, and thermal receipt view.
Future<void> showOrderDetailsModal(
  BuildContext context,
  SaleTransaction tx,
) async {
  List<Map<String, dynamic>> items = tx.items;
  if (items.isEmpty && tx.id != null) {
    items = await context.read<TransactionProvider>().getTransactionItems(tx.id!);
  }
  if (!context.mounted) return;

  final theme = Theme.of(context);
  final customerName = tx.customerName;
  final isPending =
      tx.paymentMethod.toLowerCase() == 'pending' || tx.paymentMethod.toLowerCase() == 'debt';
  final remainingBalance = (tx.totalAmount - tx.cashReceived).clamp(0.0, tx.totalAmount);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.85,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppTheme.borderColor(sheetCtx)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.borderColor(sheetCtx),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Order #${tx.id}',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(width: 10),
                              PaymentBadge(method: tx.paymentMethod),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('EEE, MMM d, yyyy • h:mm a').format(tx.date),
                            style: TextStyle(
                              color: AppTheme.mutedText(sheetCtx),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (customerName != null && customerName.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.person_outline_rounded,
                                  size: 14,
                                  color: AppTheme.accentOrange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Customer: $customerName',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        final auth = context.read<AuthProvider>();
                        showReceiptDialog(
                          context,
                          transaction: tx,
                          items: items,
                          user: auth.currentUser,
                          customerName: customerName,
                        );
                      },
                      tooltip: 'View Receipt',
                      icon: const Icon(Icons.receipt_long_rounded),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ITEMS PURCHASED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppTheme.mutedText(sheetCtx),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.subtleSurface(sheetCtx),
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          border: Border.all(color: AppTheme.borderColor(sheetCtx)),
                        ),
                        child: items.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: Text(
                                    'No items recorded for this order',
                                    style: TextStyle(
                                      color: AppTheme.mutedText(sheetCtx),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: items.length,
                                separatorBuilder: (_, _) => Divider(
                                  height: 1,
                                  color: AppTheme.borderColor(sheetCtx),
                                ),
                                itemBuilder: (ctx, index) {
                                  final item = items[index];
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.accentOrange.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '${item['quantity']}×',
                                            style: const TextStyle(
                                              color: AppTheme.accentOrange,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                              fontFeatures: AppTheme.tabularFigures,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            item['product_name'] ?? 'Unknown Item',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '₱${((item['subtotal'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            fontFeatures: AppTheme.tabularFigures,
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () => _showReturnDialog(context, tx, item),
                                          icon: const Icon(
                                            Icons.assignment_return_outlined,
                                            size: 19,
                                            color: AppTheme.accentRose,
                                          ),
                                          tooltip: 'Return Item',
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 20),

                      // Financial Breakdown
                      if (tx.discount > 0) ...[
                        ReceiptRow(
                          label: 'Subtotal',
                          value: '₱${(tx.totalAmount + tx.discount).toStringAsFixed(2)}',
                        ),
                        const SizedBox(height: 8),
                        ReceiptRow(
                          label: 'Discount',
                          value: '-₱${tx.discount.toStringAsFixed(2)}',
                          valueColor: AppTheme.accentTeal,
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (tx.paymentMethod == 'cash') ...[
                        ReceiptRow(
                          label: 'Cash Received',
                          value: '₱${tx.cashReceived.toStringAsFixed(2)}',
                        ),
                        const SizedBox(height: 8),
                        ReceiptRow(
                          label: 'Change Given',
                          value: '₱${tx.change.toStringAsFixed(2)}',
                          valueColor: AppTheme.accentTeal,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (isPending) ...[
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accentAmber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.accentAmber.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.pending_actions_rounded,
                                color: AppTheme.accentAmber,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Pending Balance Due',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: AppTheme.accentAmber,
                                      ),
                                    ),
                                    if (tx.cashReceived > 0)
                                      Text(
                                        'Deposit Paid: ₱${tx.cashReceived.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.mutedText(sheetCtx),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                '₱${remainingBalance.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: AppTheme.accentAmber,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      const Divider(height: 16),
                      ReceiptRow(
                        label: 'Total Amount',
                        value: '₱${tx.totalAmount.toStringAsFixed(2)}',
                        isTotal: true,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPending) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _showCollectPaymentDialog(
                              context,
                              tx: tx,
                              remainingBalance: remainingBalance,
                              customerName: customerName,
                              parentSheetContext: sheetCtx,
                            );
                          },
                          icon: const Icon(Icons.payments_rounded, size: 20),
                          label: Text(
                            'Collect Payment (₱${remainingBalance.toStringAsFixed(2)})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              final auth = context.read<AuthProvider>();
                              showReceiptDialog(
                                context,
                                transaction: tx,
                                items: items,
                                user: auth.currentUser,
                                customerName: customerName,
                              );
                            },
                            icon: const Icon(
                              Icons.receipt_long_rounded,
                              size: 18,
                            ),
                            label: const Text('Thermal Receipt'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(sheetCtx),
                            child: const Text('Done'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _showCollectPaymentDialog(
  BuildContext context, {
  required SaleTransaction tx,
  required double remainingBalance,
  required String? customerName,
  required BuildContext parentSheetContext,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalCtx) => CollectPaymentSheet(
      tx: tx,
      remainingBalance: remainingBalance,
      customerName: customerName,
      onPaymentSuccess: () {
        Navigator.pop(modalCtx);
        Navigator.pop(parentSheetContext);
      },
    ),
  );
}

void _showReturnDialog(
  BuildContext context,
  SaleTransaction tx,
  Map<String, dynamic> item,
) async {
  final reasonController = TextEditingController();
  final quantityController = TextEditingController(
    text: item['quantity'].toString(),
  );
  final maxQty = (item['quantity'] as num?)?.toInt() ?? 1;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        'Return ${item['product_name']}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: quantityController,
            decoration: InputDecoration(
              labelText: 'Quantity to Return (Max: $maxQty)',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: reasonController,
            decoration: const InputDecoration(
              labelText: 'Reason for Return',
              hintText: 'e.g. Damaged, Expired, Wrong item',
            ),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final qty = int.tryParse(quantityController.text) ?? 0;
            if (qty <= 0 || qty > maxQty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invalid quantity')),
              );
              return;
            }
            if (reasonController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please provide a reason')),
              );
              return;
            }
            Navigator.pop(ctx, true);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentRose,
            minimumSize: const Size(120, 44),
          ),
          child: const Text('Process Return'),
        ),
      ],
    ),
  );

  if (confirmed == true && context.mounted) {
    final newStock = await context.read<TransactionProvider>().processReturn(
      transactionId: tx.id!,
      productId: item['product_id'],
      quantity: int.parse(quantityController.text),
      reason: reasonController.text.trim(),
    );

    if (newStock != null && context.mounted) {
      if (newStock >= 0) {
        context.read<ProductProvider>().applyStockLevels({item['product_id']: newStock});
      } else {
        context.read<ProductProvider>().fetchProducts(silent: true);
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Return processed and stock restored'),
          backgroundColor: AppTheme.accentTeal,
        ),
      );
    } else if (context.mounted) {
      final err = context.read<TransactionProvider>().lastActionError ??
          'Failed to process return';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: AppTheme.accentRose,
        ),
      );
    }
  }
}

class PaymentBadge extends StatelessWidget {
  final String method;

  const PaymentBadge({super.key, required this.method});

  @override
  Widget build(BuildContext context) {
    final m = method.toLowerCase();
    final isGcash = m == 'gcash';
    final isPending = m == 'pending' || m == 'debt';
    final color = isPending
        ? AppTheme.accentAmber
        : (isGcash ? AppTheme.accentIndigo : AppTheme.accentTeal);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: isPending
            ? Border.all(
                color: AppTheme.accentAmber.withValues(alpha: 0.35),
                width: 1,
              )
            : null,
      ),
      child: Text(
        isPending ? 'PENDING' : method.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;
  final Color? valueColor;

  const ReceiptRow({
    super.key,
    required this.label,
    required this.value,
    this.isTotal = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 16 : 13,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
            color: isTotal ? null : AppTheme.mutedText(context),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 20 : 14,
            fontWeight: FontWeight.w800,
            color: valueColor ?? (isTotal ? AppTheme.accentOrange : null),
            fontFeatures: AppTheme.tabularFigures,
          ),
        ),
      ],
    );
  }
}

class CollectPaymentSheet extends StatefulWidget {
  final SaleTransaction tx;
  final double remainingBalance;
  final String? customerName;
  final VoidCallback onPaymentSuccess;

  const CollectPaymentSheet({
    super.key,
    required this.tx,
    required this.remainingBalance,
    required this.customerName,
    required this.onPaymentSuccess,
  });

  @override
  State<CollectPaymentSheet> createState() => _CollectPaymentSheetState();
}

class _CollectPaymentSheetState extends State<CollectPaymentSheet> {
  String _selectedMethod = 'cash'; // 'cash' or 'gcash'
  late final TextEditingController _cashController;
  double _cashTendered = 0.0;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _cashController = TextEditingController();
  }

  @override
  void dispose() {
    _cashController.dispose();
    super.dispose();
  }

  void _setExact() {
    setState(() {
      _cashTendered = widget.remainingBalance;
      _cashController.text = widget.remainingBalance.toStringAsFixed(2);
    });
  }

  void _setDenomination(double amount) {
    setState(() {
      _cashTendered = amount;
      _cashController.text = amount.toStringAsFixed(0);
    });
  }

  List<double> get _quickDenominations {
    final baseList = [50.0, 100.0, 200.0, 500.0, 1000.0];
    final valid = baseList.where((d) => d > widget.remainingBalance).toList();
    if (valid.isEmpty) {
      final nextRound = ((widget.remainingBalance / 500).ceil() * 500).toDouble();
      if (nextRound > widget.remainingBalance) {
        valid.add(nextRound);
      }
      valid.add(nextRound + 500);
    }
    return valid;
  }

  Future<void> _submitPayment() async {
    if (_isSubmitting) return;

    if (_selectedMethod == 'cash' && _cashTendered <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an amount to pay or deposit.'),
          backgroundColor: AppTheme.accentRose,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final paymentAmount =
        _selectedMethod == 'cash' ? _cashTendered : widget.remainingBalance;

    final isFullyPaid = paymentAmount >= widget.remainingBalance;
    final change = (_selectedMethod == 'cash' && paymentAmount > widget.remainingBalance)
        ? (paymentAmount - widget.remainingBalance)
        : 0.0;

    final totalCashReceived =
        isFullyPaid ? widget.tx.totalAmount : (widget.tx.cashReceived + paymentAmount);

    final newPaymentMethod = isFullyPaid ? _selectedMethod : 'pending';

    final success = await context.read<TransactionProvider>().markTransactionPaid(
      transactionId: widget.tx.id!,
      newPaymentMethod: newPaymentMethod,
      cashReceived: totalCashReceived,
      changeAmount: change,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      widget.onPaymentSuccess();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isFullyPaid
                      ? 'Order #${widget.tx.id} marked as Paid (${_selectedMethod.toUpperCase()})'
                      : 'Downpayment of ₱${paymentAmount.toStringAsFixed(2)} recorded for Order #${widget.tx.id}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update transaction. Please try again.'),
          backgroundColor: AppTheme.accentRose,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCash = _selectedMethod == 'cash';
    final changeDue = (_cashTendered - widget.remainingBalance).clamp(0.0, double.infinity);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Container(
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.borderColor(context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Collect Payment',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Order #${widget.tx.id}${widget.customerName != null && widget.customerName!.isNotEmpty ? ' • ${widget.customerName}' : ''}',
                              style: TextStyle(
                                color: AppTheme.mutedText(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Unpaid Balance Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.subtleSurface(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.borderColor(context)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'UNPAID BALANCE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  color: AppTheme.mutedText(context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '₱${widget.remainingBalance.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.accentOrange,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.accentAmber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'PENDING',
                              style: TextStyle(
                                color: AppTheme.accentAmber,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Payment Method Choice
                    Text(
                      'RECEIVE PAYMENT VIA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: AppTheme.mutedText(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: MethodChoiceCard(
                            label: 'Cash',
                            icon: Icons.payments_rounded,
                            isSelected: isCash,
                            onTap: () => setState(() => _selectedMethod = 'cash'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MethodChoiceCard(
                            label: 'GCash',
                            icon: Icons.account_balance_wallet_rounded,
                            isSelected: !isCash,
                            onTap: () => setState(() => _selectedMethod = 'gcash'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Cash Controls
                    if (isCash) ...[
                      Text(
                        'CASH TENDERED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: AppTheme.mutedText(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _cashController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                        decoration: const InputDecoration(
                          prefixIcon: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              '₱',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                          hintText: '0.00 (Enter full or partial amount)',
                        ),
                        onChanged: (val) {
                          setState(() {
                            _cashTendered = double.tryParse(val) ?? 0.0;
                          });
                        },
                      ),
                      const SizedBox(height: 12),

                      // Quick Cash Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ActionChip(
                              label: Text('Exact ₱${widget.remainingBalance.toStringAsFixed(2)}'),
                              onPressed: _setExact,
                              backgroundColor: AppTheme.subtleSurface(context),
                            ),
                            const SizedBox(width: 8),
                            ..._quickDenominations.map(
                              (denom) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  label: Text('₱${denom.toStringAsFixed(0)}'),
                                  onPressed: () => _setDenomination(denom),
                                  backgroundColor: AppTheme.subtleSurface(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (_cashTendered > 0 && _cashTendered < widget.remainingBalance) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.accentAmber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.accentAmber.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Remaining Balance After Deposit',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.accentAmber,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    'Order stays pending until fully paid',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.mutedText(context),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '₱${(widget.remainingBalance - _cashTendered).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  color: AppTheme.accentAmber,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.accentTeal.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.accentTeal.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Change Due',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.accentTeal,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '₱${changeDue.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  color: AppTheme.accentTeal,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ] else ...[
                      // GCash Banner
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.accentIndigo.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.accentIndigo.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.accentIndigo.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.qr_code_2_rounded,
                                color: AppTheme.accentIndigo,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'GCash Mobile Payment',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Collect exact ₱${widget.remainingBalance.toStringAsFixed(2)} from customer via QR or Express Send.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.mutedText(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Confirm Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _submitPayment,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                (_selectedMethod == 'cash' &&
                                        _cashTendered > 0 &&
                                        _cashTendered < widget.remainingBalance)
                                    ? Icons.payments_outlined
                                    : Icons.check_circle_rounded,
                                size: 20,
                              ),
                        label: Text(
                          _isSubmitting
                              ? 'Saving Payment...'
                              : ((_selectedMethod == 'cash' &&
                                      _cashTendered > 0 &&
                                      _cashTendered < widget.remainingBalance)
                                  ? 'Save Downpayment (₱${_cashTendered.toStringAsFixed(2)})'
                                  : 'Confirm & Mark as Paid'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (_selectedMethod == 'cash' &&
                                  _cashTendered > 0 &&
                                  _cashTendered < widget.remainingBalance)
                              ? AppTheme.accentAmber
                              : const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MethodChoiceCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const MethodChoiceCard({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = AppTheme.accentOrange;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.1)
              : AppTheme.subtleSurface(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? activeColor : AppTheme.borderColor(context),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? activeColor : AppTheme.mutedText(context),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? activeColor : null,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

