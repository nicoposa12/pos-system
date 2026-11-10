class SaleTransaction {
  final int? id;
  final int userId;
  final double totalAmount;
  final double discount;
  final double cashReceived;
  final double change;
  final String paymentMethod; // 'cash', 'gcash', 'debt'
  final DateTime date;

  /// Customer name of the linked debt record (pending / utang sales).
  final String? customerName;

  /// Line items: `product_id`, `product_name`, `category`, `quantity`, `subtotal`.
  final List<Map<String, dynamic>> items;

  /// Server `updated_at` (ISO-8601), used as the incremental delta-sync cursor.
  final String? updatedAt;

  SaleTransaction({
    this.id,
    required this.userId,
    required this.totalAmount,
    this.discount = 0.0,
    this.cashReceived = 0.0,
    this.change = 0.0,
    this.paymentMethod = 'cash',
    required this.date,
    this.customerName,
    this.items = const [],
    this.updatedAt,
  });

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  /// Builds a transaction from the API payload (`/transactions`), including
  /// eager-loaded `items.product`, `debt`, and `returns` relations.
  factory SaleTransaction.fromJson(Map<String, dynamic> json) {
    // Build return map by product_id
    final returnMap = <int, int>{};
    final rawReturns = json['returns'];
    if (rawReturns is List) {
      for (final r in rawReturns) {
        if (r is Map) {
          final pid = int.tryParse(r['product_id']?.toString() ?? '') ?? 0;
          final qty = int.tryParse(r['quantity']?.toString() ?? '') ?? 0;
          returnMap[pid] = (returnMap[pid] ?? 0) + qty;
        }
      }
    }

    final rawItems = json['items'];
    final items = <Map<String, dynamic>>[];
    double computedSubtotalSum = 0.0;

    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final product = raw['product'] is Map ? raw['product'] as Map : null;
        final productId = int.tryParse(raw['product_id']?.toString() ?? '') ?? 0;
        final originalQty = int.tryParse(raw['quantity']?.toString() ?? '') ?? 1;
        final rawSubtotal = _toDouble(raw['subtotal']);
        final unitPrice = originalQty > 0 ? (rawSubtotal / originalQty) : 0.0;

        final returnedQty = returnMap[productId] ?? 0;
        final netQty = (originalQty - returnedQty).clamp(0, originalQty);
        final netSubtotal = double.parse((netQty * unitPrice).toStringAsFixed(2));

        computedSubtotalSum += netSubtotal;

        items.add({
          'product_id': productId,
          'product_name': product?['name']?.toString() ?? 'Item #$productId',
          'category': product?['category']?.toString(),
          'quantity': netQty,
          'original_quantity': originalQty,
          'returned_quantity': returnedQty,
          'unit_price': unitPrice,
          'subtotal': netSubtotal,
        });
      }
    }

    final debt = json['debt'] is Map ? json['debt'] as Map : null;
    final discount = _toDouble(json['discount']);
    final rawTotal = _toDouble(json['total_amount']);

    // When returns exist, accurately reflect the net total amount
    final netTotal = returnMap.isNotEmpty
        ? (computedSubtotalSum - discount).clamp(0.0, double.infinity)
        : rawTotal;

    // Prefer created_at as it is the authoritative server UTC timestamp.
    // Fall back to date, then now(). Always convert to the device's local timezone.
    final rawDateStr = (json['created_at'] != null && json['created_at'].toString().trim().isNotEmpty)
        ? json['created_at'].toString().trim()
        : (json['date'] != null ? json['date'].toString().trim() : '');
    final parsedDate = (DateTime.tryParse(rawDateStr) ?? DateTime.now()).toLocal();

    return SaleTransaction(
      id: int.tryParse(json['id']?.toString() ?? ''),
      userId: int.tryParse(json['user_id']?.toString() ?? '') ?? 0,
      totalAmount: netTotal,
      discount: discount,
      cashReceived: _toDouble(json['cash_received']),
      change: _toDouble(json['change_amount']),
      paymentMethod: json['payment_method']?.toString() ?? 'cash',
      date: parsedDate,
      customerName: debt?['customer_name']?.toString(),
      items: items,
      updatedAt: json['updated_at']?.toString(),
    );
  }
}
