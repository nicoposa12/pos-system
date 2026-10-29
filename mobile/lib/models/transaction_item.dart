class TransactionItem {
  final int? id;
  final int transactionId;
  final int productId;
  final int quantity;
  final double subtotal;
  // Optional: Add product name/price for history display without joins
  final String? productName;
  final double? unitPrice;

  TransactionItem({
    this.id,
    required this.transactionId,
    required this.productId,
    required this.quantity,
    required this.subtotal,
    this.productName,
    this.unitPrice,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'transaction_id': transactionId,
      'product_id': productId,
      'quantity': quantity,
      'subtotal': subtotal,
    };
  }

  factory TransactionItem.fromMap(Map<String, dynamic> map) {
    return TransactionItem(
      id: map['id'],
      transactionId: map['transaction_id'],
      productId: map['product_id'],
      quantity: map['quantity'],
      subtotal: map['subtotal'],
    );
  }
}
