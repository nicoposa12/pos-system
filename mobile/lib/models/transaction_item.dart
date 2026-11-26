class TransactionItem {
  final int? id;
  final int transactionId;
  final int productId;
  final double quantity;
  final double subtotal;
  final double? unitCost;
  // Optional: Add product name/price for history display without joins
  final String? productName;
  final double? unitPrice;

  TransactionItem({
    this.id,
    required this.transactionId,
    required this.productId,
    required this.quantity,
    required this.subtotal,
    this.unitCost,
    this.productName,
    this.unitPrice,
  });

  double? get totalCost => unitCost != null ? unitCost! * quantity : null;
  double? get profit => totalCost != null ? subtotal - totalCost! : null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'transaction_id': transactionId,
      'product_id': productId,
      'quantity': quantity,
      'subtotal': subtotal,
      'unit_cost': ?unitCost,
    };
  }

  factory TransactionItem.fromMap(Map<String, dynamic> map) {
    final rawCost = map['unit_cost'];
    return TransactionItem(
      id: (map['id'] as num?)?.toInt(),
      transactionId: (map['transaction_id'] as num?)?.toInt() ?? 0,
      productId: (map['product_id'] as num?)?.toInt() ?? 0,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 1.0,
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
      unitCost: rawCost is num
          ? rawCost.toDouble()
          : double.tryParse(rawCost?.toString() ?? ''),
    );
  }
}
