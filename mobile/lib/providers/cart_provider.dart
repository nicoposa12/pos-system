import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/transaction.dart';
import '../models/transaction_item.dart';
import '../data/database_helper.dart';
import '../services/api_service.dart';

class CartItem {
  final Product product;
  final String? variantName;
  final double price;
  int quantity;

  CartItem({
    required this.product,
    this.variantName,
    required this.price,
    this.quantity = 1,
  });

  String get displayName => variantName != null ? '${product.name} ($variantName)' : product.name;
  double get subtotal => price * quantity;
}

class CartProvider with ChangeNotifier {
  final Map<String, CartItem> _items = {}; // Key: "productId_variantName"
  int? _userId;

  Map<String, CartItem> get items => {..._items};

  int get itemCount => _items.values.fold(0, (sum, item) => sum + item.quantity);

  void setUserId(int userId) {
    _userId = userId;
  }

  double get totalAmount {
    double total = 0.0;
    _items.forEach((key, cartItem) {
      total += cartItem.subtotal;
    });
    return total;
  }

  void addItem(Product product, {ProductVariant? variant}) {
    final String variantKey = variant != null ? '${product.id}_${variant.name}' : '${product.id}_base';
    final double price = variant?.price ?? product.price;

    if (_items.containsKey(variantKey)) {
      // Check total quantity of this product in cart vs stock
      int totalInCart = _items.values
          .where((item) => item.product.id == product.id)
          .fold(0, (sum, item) => sum + item.quantity);

      if (totalInCart < product.stock) {
        _items.update(
          variantKey,
          (existingItem) => CartItem(
            product: existingItem.product,
            variantName: existingItem.variantName,
            price: existingItem.price,
            quantity: existingItem.quantity + 1,
          ),
        );
      }
    } else {
      if (product.stock > 0) {
        _items.putIfAbsent(
          variantKey,
          () => CartItem(
            product: product,
            variantName: variant?.name,
            price: price,
          ),
        );
      }
    }
    notifyListeners();
  }

  void removeSingleItem(String variantKey) {
    if (!_items.containsKey(variantKey)) return;

    if (_items[variantKey]!.quantity > 1) {
      _items.update(
        variantKey,
        (existingItem) => CartItem(
          product: existingItem.product,
          variantName: existingItem.variantName,
          price: existingItem.price,
          quantity: existingItem.quantity - 1,
        ),
      );
    } else {
      _items.remove(variantKey);
    }
    notifyListeners();
  }

  void removeItem(String variantKey) {
    _items.remove(variantKey);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  Future<Map<String, dynamic>?> checkout({
    double discount = 0.0, 
    double cashReceived = 0.0,
    String paymentMethod = 'cash',
    String? customerName,
  }) async {
    if (_items.isEmpty || _userId == null) return null;

    final finalTotal = totalAmount - discount;
    final change = cashReceived > 0 ? cashReceived - finalTotal : 0.0;

    final transaction = SaleTransaction(
      userId: _userId!,
      totalAmount: finalTotal,
      discount: discount,
      cashReceived: cashReceived,
      change: change > 0 ? change : 0.0,
      paymentMethod: paymentMethod,
      date: DateTime.now(),
    );

    final cartItemsList = _items.values.toList();
    final transactionItems = cartItemsList.map((cartItem) {
      return TransactionItem(
        transactionId: 0,
        productId: cartItem.product.id!,
        quantity: cartItem.quantity,
        subtotal: cartItem.subtotal,
      );
    }).toList();

    try {
      final transactionId = await DatabaseHelper.instance.createTransaction(transaction, transactionItems);
      
      // Attempt immediate online push
      if (ApiService.instance.isAuthenticated) {
        try {
          await ApiService.instance.createTransaction({
            'total_amount': transaction.totalAmount,
            'discount': transaction.discount,
            'cash_received': transaction.cashReceived,
            'change_amount': transaction.change,
            'payment_method': transaction.paymentMethod,
            'customer_name': customerName,
            'date': transaction.date.toIso8601String(),
            'items': transactionItems.map((ti) => {
              'product_id': ti.productId,
              'quantity': ti.quantity,
              'subtotal': ti.subtotal,
            }).toList(),
          });
          await DatabaseHelper.instance.markTransactionsSynced([transactionId]);
        } catch (e) {
          debugPrint('Online checkout push skipped (will sync later via SyncService): $e');
        }
      }

      final completedTransaction = SaleTransaction(
        id: transactionId,
        userId: transaction.userId,
        totalAmount: transaction.totalAmount,
        discount: transaction.discount,
        cashReceived: transaction.cashReceived,
        change: transaction.change,
        paymentMethod: transaction.paymentMethod,
        date: transaction.date,
      );

      final itemsForPdf = cartItemsList.map((item) => {
        'product_name': item.displayName,
        'quantity': item.quantity,
        'subtotal': item.subtotal,
      }).toList();

      clear();
      return {
        'transaction': completedTransaction,
        'items': itemsForPdf,
      };
    } catch (e) {
      debugPrint('Checkout error: $e');
      return null;
    }
  }
}
