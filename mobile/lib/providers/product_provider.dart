import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/realtime_service.dart';

/// Store inventory, loaded from the cloud API and held in memory.
///
/// Mutations go straight to the API and the returned server record is applied
/// in place, so the list never needs a full reload after a local change.
class ProductProvider with ChangeNotifier {
  List<Product> _products = [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  String _searchQuery = '';
  String _selectedCategory = 'All';
  int? _userId;
  Future<void>? _inFlight;

  // Memoized derived views (recomputed only when inputs change)
  List<Product>? _filteredCache;
  List<String>? _categoriesCache;
  List<Product>? _lowStockCache;

  ProductProvider() {
    RealtimeService.instance.addProductListener(_onRemoteChange);
  }

  @override
  void dispose() {
    RealtimeService.instance.removeProductListener(_onRemoteChange);
    super.dispose();
  }

  void _onRemoteChange() {
    if (_userId != null) fetchProducts(silent: true);
  }

  void _setProducts(List<Product> products) {
    _products = products;
    _invalidate();
  }

  void _invalidate() {
    _filteredCache = null;
    _categoriesCache = null;
    _lowStockCache = null;
  }

  List<Product> get allProducts => List.unmodifiable(_products);

  List<Product> get products {
    return _filteredCache ??= List.unmodifiable(() {
      Iterable<Product> filtered = _products;

      if (_selectedCategory != 'All') {
        filtered = filtered.where((p) => p.category == _selectedCategory);
      }

      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        filtered = filtered.where(
          (p) =>
              p.name.toLowerCase().contains(query) ||
              (p.barcode != null && p.barcode!.toLowerCase().contains(query)),
        );
      }

      return filtered.toList();
    }());
  }

  String get selectedCategory => _selectedCategory;

  List<String> get categories {
    return _categoriesCache ??= () {
      final Set<String> cats = {'All'};
      for (var p in _products) {
        if (p.category != null && p.category!.isNotEmpty) {
          cats.add(p.category!);
        }
      }
      return cats.toList()
        ..sort((a, b) => a == 'All' ? -1 : (b == 'All' ? 1 : a.compareTo(b)));
    }();
  }

  bool get isLoading => _isLoading;

  /// Last load error (e.g. no internet), or `null` when the data is current.
  String? get errorMessage => _errorMessage;

  void setUserId(int userId) {
    if (_userId != userId) {
      _userId = userId;
      _hasLoaded = false;
      _setProducts([]);
      fetchProducts();
    }
  }

  /// Loads the catalog from the API. Concurrent calls share one request, and
  /// once data is loaded refreshes run silently (stale-while-revalidate).
  Future<void> fetchProducts({bool silent = false}) {
    if (_userId == null) return Future.value();
    return _inFlight ??= _load(silent: silent || _hasLoaded).whenComplete(() {
      _inFlight = null;
    });
  }

  Future<void> _load({required bool silent}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    final requestedFor = _userId;
    try {
      final remote = await ApiService.instance.getProducts();
      if (requestedFor != _userId) return; // session changed mid-request
      final list = remote
          .whereType<Map>()
          .map((p) => Product.fromJson(Map<String, dynamic>.from(p)))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _setProducts(list);
      _hasLoaded = true;
      _errorMessage = null;
    } catch (e) {
      debugPrint('[ProductProvider] fetch error: $e');
      _errorMessage = ApiService.describeError(e, 'Unable to load products.');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    _filteredCache = null;
    notifyListeners();
  }

  void setCategory(String category) {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    _filteredCache = null;
    notifyListeners();
  }

  Product _fromResponse(Map<String, dynamic> res, Product fallback) {
    final raw = res['product'];
    if (raw is Map) {
      return Product.fromJson(Map<String, dynamic>.from(raw));
    }
    return fallback;
  }

  void _upsert(Product product) {
    final updated = List<Product>.of(_products);
    final index = updated.indexWhere((p) => p.id == product.id);
    if (index >= 0) {
      updated[index] = product;
    } else {
      updated.add(product);
    }
    updated.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _setProducts(updated);
    notifyListeners();
  }

  /// Creates the product on the server. Throws with a readable message on failure.
  /// Returns `true` once the product is saved to the cloud.
  Future<bool> addProduct(Product product) async {
    try {
      final res = await ApiService.instance.createProduct(
        name: product.name,
        price: product.price,
        stock: product.stock,
        category: product.category,
        barcode: product.barcode,
        variants: product.variantsPayload,
        imageFilePath: product.imagePath,
      );
      _upsert(_fromResponse(res, product));
      return true;
    } catch (e) {
      throw Exception(ApiService.describeError(e, 'Failed to save product.'));
    }
  }

  /// Updates the product on the server. Throws with a readable message on failure.
  Future<void> updateProduct(Product product) async {
    if (product.id == null) return;
    try {
      final res = await ApiService.instance.updateProduct(
        product.id!,
        name: product.name,
        price: product.price,
        stock: product.stock,
        category: product.category,
        barcode: product.barcode,
        variants: product.variantsPayload,
        imageFilePath: product.imagePath,
      );
      _upsert(_fromResponse(res, product));
    } catch (e) {
      throw Exception(ApiService.describeError(e, 'Failed to update product.'));
    }
  }

  /// Deletes the product on the server. Throws with a readable message on failure.
  Future<void> deleteProduct(int id) async {
    try {
      await ApiService.instance.deleteProduct(id);
      _setProducts(_products.where((p) => p.id != id).toList());
      notifyListeners();
    } catch (e) {
      throw Exception(ApiService.describeError(e, 'Failed to delete product.'));
    }
  }

  /// Applies authoritative stock levels returned by the server (after a sale
  /// or return) without reloading the whole catalog.
  void applyStockLevels(Map<int, int> stockByProductId) {
    if (stockByProductId.isEmpty) return;
    var changed = false;
    final updated = _products.map((p) {
      final stock = p.id != null ? stockByProductId[p.id] : null;
      if (stock == null || stock == p.stock) return p;
      changed = true;
      return p.copyWith(stock: stock);
    }).toList();
    if (!changed) return;
    _setProducts(updated);
    notifyListeners();
  }

  List<Product> get lowStockProducts {
    return _lowStockCache ??=
        List.unmodifiable(_products.where((p) => p.stock <= 5));
  }

  void clearData() {
    _setProducts([]);
    _userId = null;
    _hasLoaded = false;
    _errorMessage = null;
    _selectedCategory = 'All';
    _searchQuery = '';
    notifyListeners();
  }
}
