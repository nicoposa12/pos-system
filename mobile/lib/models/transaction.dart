class SaleTransaction {
  final int? id;
  final int userId;
  final double totalAmount;
  final double discount;
  final double cashReceived;
  final double change;
  final String paymentMethod; // 'cash', 'gcash', 'debt'
  final DateTime date;
  final bool isSynced;

  SaleTransaction({
    this.id,
    required this.userId,
    required this.totalAmount,
    this.discount = 0.0,
    this.cashReceived = 0.0,
    this.change = 0.0,
    this.paymentMethod = 'cash',
    required this.date,
    this.isSynced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'total_amount': totalAmount,
      'discount': discount,
      'cash_received': cashReceived,
      'change_amount': change,
      'payment_method': paymentMethod,
      'date': date.toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
    };
  }

  factory SaleTransaction.fromMap(Map<String, dynamic> map) {
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(map['date']);
    } catch (_) {
      parsedDate = DateTime.now();
    }
    return SaleTransaction(
      id: map['id'],
      userId: map['user_id'] ?? 0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      discount: (map['discount'] as num?)?.toDouble() ?? 0.0,
      cashReceived: (map['cash_received'] as num?)?.toDouble() ?? 0.0,
      change: (map['change_amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: map['payment_method'] ?? 'cash',
      date: parsedDate,
      isSynced: (map['is_synced'] == 1 || map['is_synced'] == true),
    );
  }
}
