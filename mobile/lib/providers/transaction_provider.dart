import 'package:flutter/material.dart';
import '../data/database_helper.dart';
import '../models/transaction.dart';

class TransactionProvider with ChangeNotifier {
  List<SaleTransaction> _transactions = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _categorySales = [];
  bool _isLoading = false;
  int? _userId;

  List<SaleTransaction> get transactions => _transactions;
  bool get isLoading => _isLoading;
  List<Map<String, dynamic>> get topProducts => _topProducts;
  List<Map<String, dynamic>> get categorySales => _categorySales;

  void setUserId(int? userId) {
    if (_userId != userId) {
      _userId = userId;
      _transactions = [];
      _topProducts = [];
      _categorySales = [];
      fetchTransactions();
    }
  }

  Future<void> fetchTransactions() async {
    if (_userId == null) return;

    _isLoading = true;
    notifyListeners();

    _transactions = await DatabaseHelper.instance.readAllTransactions(userId: _userId!);
    _topProducts = await DatabaseHelper.instance.getTopSellingProducts(_userId!);
    _categorySales = await DatabaseHelper.instance.getCategorySales(_userId!);
    
    _isLoading = false;
    notifyListeners();
  }

  double get dailyTotal {
    final today = DateTime.now();
    return _transactions
        .where((t) => 
            t.date.year == today.year && 
            t.date.month == today.month && 
            t.date.day == today.day)
        .fold(0.0, (sum, t) => sum + t.totalAmount);
  }

  double get weeklyTotal {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    return _transactions
        .where((t) => t.date.isAfter(weekAgo))
        .fold(0.0, (sum, t) => sum + t.totalAmount);
  }

  double get monthlyTotal {
    final today = DateTime.now();
    return _transactions
        .where((t) => 
            t.date.year == today.year && 
            t.date.month == today.month)
        .fold(0.0, (sum, t) => sum + t.totalAmount);
  }

  double get yearlyTotal {
    final today = DateTime.now();
    return _transactions
        .where((t) => t.date.year == today.year)
        .fold(0.0, (sum, t) => sum + t.totalAmount);
  }

  // Get sales data for the last 7 days
  Map<String, double> getWeeklySalesData() {
    final now = DateTime.now();
    final Map<String, double> data = {};

    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      // Use a consistent ISO format for the key
      final dayKey = DateTime(date.year, date.month, date.day).toIso8601String().split('T')[0];
      
      final dayTotal = _transactions
          .where((t) => 
              t.date.year == date.year && 
              t.date.month == date.month && 
              t.date.day == date.day)
          .fold(0.0, (sum, t) => sum + t.totalAmount);
      
      data[dayKey] = dayTotal;
    }
    return data;
  }

  int get dailyTransactionCount {
    final today = DateTime.now();
    return _transactions
        .where((t) => 
            t.date.year == today.year && 
            t.date.month == today.month && 
            t.date.day == today.day)
        .length;
  }

  Future<List<Map<String, dynamic>>> getTransactionItems(int id) async {
    return await DatabaseHelper.instance.readTransactionItems(id);
  }

  Future<bool> processReturn({
    required int transactionId,
    required int productId,
    required int quantity,
    required String reason,
  }) async {
    if (_userId == null) return false;

    try {
      await DatabaseHelper.instance.createReturn(
        userId: _userId!,
        transactionId: transactionId,
        productId: productId,
        quantity: quantity,
        reason: reason,
      );
      
      // Refresh data
      await fetchTransactions();
      return true;
    } catch (e) {
      debugPrint('Error processing return: $e');
      return false;
    }
  }

  void clearData() {
    _transactions = [];
    _userId = null;
    notifyListeners();
  }
}
