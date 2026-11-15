class SaleTransaction {
  final int? id;
  final int? orderNumber;
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

  /// Store-scoped sequential order number, falling back to [id] when absent.
  int? get displayOrderNumber => orderNumber ?? id;

  SaleTransaction({
    this.id,
    this.orderNumber,
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

  static double? _tryToDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static double _toDouble(dynamic value) => _tryToDouble(value) ?? 0.0;

  static double _roundQty(double value) =>
      double.parse(value.toStringAsFixed(3));

  static double _roundMoney(double value) =>
      double.parse(value.toStringAsFixed(2));

  /// Builds a transaction from the API payload (`/transactions`), including
  /// eager-loaded `items.product`, `debt`, and `returns` relations.
  factory SaleTransaction.fromJson(Map<String, dynamic> json) {
    // Build return map by product_id (supports decimal quantities like 0.5)
    final returnMap = <int, double>{};
    final rawReturns = json['returns'];
    if (rawReturns is List) {
      for (final r in rawReturns) {
        if (r is Map) {
          final pid = int.tryParse(r['product_id']?.toString() ?? '') ?? 0;
          final qty = _toDouble(r['quantity']);
          if (pid > 0 && qty > 0) {
            returnMap[pid] = _roundQty((returnMap[pid] ?? 0.0) + qty);
          }
        }
      }
    }

    final remainingReturns = Map<int, double>.from(returnMap);
    final rawItems = json['items'];
    final items = <Map<String, dynamic>>[];
    double computedSubtotalSum = 0.0;

    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final product = raw['product'] is Map ? raw['product'] as Map : null;
        final productId = int.tryParse(raw['product_id']?.toString() ?? '') ?? 0;
        final originalQty = _tryToDouble(raw['quantity']) ?? 1.0;
        final rawSubtotal = _toDouble(raw['subtotal']);
        final unitPrice = originalQty > 0 ? (rawSubtotal / originalQty) : 0.0;

        final returnedAvailable = remainingReturns[productId] ?? 0.0;
        final returnedQty = _roundQty(
          returnedAvailable.clamp(0.0, originalQty).toDouble(),
        );
        remainingReturns[productId] = _roundQty(
          (returnedAvailable - returnedQty).clamp(0.0, double.infinity).toDouble(),
        );

        final netQty = _roundQty(
          (originalQty - returnedQty).clamp(0.0, originalQty).toDouble(),
        );
        final netSubtotal = netQty <= 0.0
            ? 0.0
            : _roundMoney(netQty * unitPrice);

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
        ? _roundMoney((computedSubtotalSum - discount).clamp(0.0, double.infinity).toDouble())
        : rawTotal;

    // Prefer created_at as it is the authoritative server UTC timestamp.
    // Fall back to date, then now(). Always convert to the device's local timezone.
    final rawDateStr = (json['created_at'] != null && json['created_at'].toString().trim().isNotEmpty)
        ? json['created_at'].toString().trim()
        : (json['date'] != null ? json['date'].toString().trim() : '');
    final parsedDate = (DateTime.tryParse(rawDateStr) ?? DateTime.now()).toLocal();

    return SaleTransaction(
      id: int.tryParse(json['id']?.toString() ?? ''),
      orderNumber: int.tryParse(json['order_number']?.toString() ?? ''),
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
