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
  /// eager-loaded `items.product` and `debt` relations.
  factory SaleTransaction.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = <Map<String, dynamic>>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final product = raw['product'] is Map ? raw['product'] as Map : null;
        final productId = int.tryParse(raw['product_id']?.toString() ?? '') ?? 0;
        items.add({
          'product_id': productId,
          'product_name': product?['name']?.toString() ?? 'Item #$productId',
          'category': product?['category']?.toString(),
          'quantity': int.tryParse(raw['quantity']?.toString() ?? '') ?? 1,
          'subtotal': _toDouble(raw['subtotal']),
        });
      }
    }

    final debt = json['debt'] is Map ? json['debt'] as Map : null;

    return SaleTransaction(
      id: int.tryParse(json['id']?.toString() ?? ''),
      userId: int.tryParse(json['user_id']?.toString() ?? '') ?? 0,
      totalAmount: _toDouble(json['total_amount']),
      discount: _toDouble(json['discount']),
      cashReceived: _toDouble(json['cash_received']),
      change: _toDouble(json['change_amount']),
      paymentMethod: json['payment_method']?.toString() ?? 'cash',
      date: (DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now())
          .toLocal(),
      customerName: debt?['customer_name']?.toString(),
      items: items,
      updatedAt: json['updated_at']?.toString(),
    );
  }
}
