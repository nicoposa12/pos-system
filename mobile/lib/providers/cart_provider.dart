import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/transaction.dart';
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

  String get displayName =>
      variantName != null ? '${product.name} ($variantName)' : product.name;
  double get subtotal => price * quantity;
}

class CartProvider with ChangeNotifier {
  final Map<String, CartItem> _items = {}; // Key: "productId_variantName"
  int? _userId;
  String? _lastError;

  Map<String, CartItem> get items => {..._items};
  int get itemCount => _items.values.fold(0, (sum, item) => sum + item.quantity);
  String? get lastError => _lastError;

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
    final String variantKey = variant != null
        ? '${product.id}_${variant.name}'
        : '${product.id}_base';
    final double price = variant?.price ?? product.price;
    final int itemStock = variant?.stock ?? product.stock;

    if (_items.containsKey(variantKey)) {
      if (variant?.stock != null) {
        if (_items[variantKey]!.quantity < variant!.stock!) {
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
      }
    } else {
      if (itemStock > 0) {
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

  bool updateQuantity(String variantKey, int newQuantity) {
    if (!_items.containsKey(variantKey)) return false;

    if (newQuantity <= 0) {
      _items.remove(variantKey);
      notifyListeners();
      return true;
    }

    final item = _items[variantKey]!;
    final product = item.product;
    ProductVariant? matchedVariant;
    if (item.variantName != null) {
      final matches = product.variants
          .where((v) => v.name == item.variantName)
          .toList();
      if (matches.isNotEmpty) matchedVariant = matches.first;
    }

    int maxAllowed;
    if (matchedVariant?.stock != null) {
      maxAllowed = matchedVariant!.stock!;
    } else {
      final otherLinesCount = _items.entries
          .where((e) => e.key != variantKey && e.value.product.id == product.id)
          .fold(0, (sum, e) => sum + e.value.quantity);
      maxAllowed = (product.stock - otherLinesCount).clamp(0, product.stock);
    }

    final finalQuantity = newQuantity > maxAllowed ? maxAllowed : newQuantity;

    _items.update(
      variantKey,
      (existingItem) => CartItem(
        product: existingItem.product,
        variantName: existingItem.variantName,
        price: existingItem.price,
        quantity: finalQuantity,
      ),
    );
    notifyListeners();
    return finalQuantity == newQuantity;
  }

  void removeItem(String variantKey) {
    _items.remove(variantKey);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  /// Processes checkout directly on the server API.
  /// Returns a map with completed [SaleTransaction] and receipt items, or null on failure.
  Future<Map<String, dynamic>?> checkout({
    double discount = 0.0,
    double cashReceived = 0.0,
    String paymentMethod = 'cash',
    String? customerName,
  }) async {
    _lastError = null;
    if (_items.isEmpty || _userId == null) return null;

    final finalTotal = totalAmount - discount;
    final change = cashReceived > 0 ? cashReceived - finalTotal : 0.0;
    final cartItemsList = _items.values.toList();

    final payloadItems = cartItemsList.map((cartItem) {
      return {
        'product_id': cartItem.product.id!,
        'quantity': cartItem.quantity,
        'subtotal': cartItem.subtotal,
      };
    }).toList();

    try {
      final res = await ApiService.instance.createTransaction({
        'total_amount': finalTotal,
        'discount': discount,
        'cash_received': cashReceived,
        'change_amount': change > 0 ? change : 0.0,
        'payment_method': paymentMethod,
        'customer_name': customerName,
        'date': DateTime.now().toUtc().toIso8601String(),
        'items': payloadItems,
      });

      final txJson = res['transaction'] is Map
          ? Map<String, dynamic>.from(res['transaction'] as Map)
          : <String, dynamic>{};

      final completedTransaction = SaleTransaction.fromJson(txJson);

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
      debugPrint('[CartProvider] Checkout error: $e');
      _lastError = ApiService.describeError(e, 'Transaction failed. Please try again.');
      return null;
    }
  }
}
