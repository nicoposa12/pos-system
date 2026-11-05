import 'package:flutter/material.dart';
import '../data/database_helper.dart';
import '../models/product.dart';
import '../services/api_service.dart';

class ProductProvider with ChangeNotifier {
  List<Product> _products = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String _selectedCategory = 'All';
  int? _userId;

  List<Product> get allProducts => List.unmodifiable(_products);

  List<Product> get products {
    List<Product> filtered = _products;

    if (_selectedCategory != 'All') {
      filtered = filtered
          .where((p) => p.category == _selectedCategory)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered
          .where(
            (p) =>
                p.name.toLowerCase().contains(query) ||
                (p.barcode != null && p.barcode!.toLowerCase().contains(query)),
          )
          .toList();
    }

    return filtered;
  }

  String get selectedCategory => _selectedCategory;

  List<String> get categories {
    final Set<String> cats = {'All'};
    for (var p in _products) {
      if (p.category != null && p.category!.isNotEmpty) {
        cats.add(p.category!);
      }
    }
    return cats.toList()
      ..sort((a, b) => a == 'All' ? -1 : (b == 'All' ? 1 : a.compareTo(b)));
  }

  bool get isLoading => _isLoading;

  void setUserId(int userId) {
    if (_userId != userId) {
      _userId = userId;
      _products = [];
      fetchProducts();
    }
  }

  Future<void> fetchProducts() async {
    if (_userId == null) return;

    _isLoading = true;
    notifyListeners();

    // 1. Try fetching from Cloud API if authenticated
    if (ApiService.instance.isAuthenticated) {
      try {
        final remote = await ApiService.instance.getProducts();
        if (remote.isNotEmpty) {
          for (var item in remote) {
            final remoteId = item['id'] as int;
            final local = await DatabaseHelper.instance.readProduct(remoteId);

            final remoteImagePath = item['image_path'] as String?;
            final String? finalImagePath = (remoteImagePath != null && remoteImagePath.trim().isNotEmpty)
                ? remoteImagePath.trim()
                : local?.imagePath;

            final p = Product(
              id: remoteId,
              userId: _userId!,
              name: item['name'] ?? '',
              category: item['category'],
              price: (item['price'] as num?)?.toDouble() ?? 0.0,
              stock: item['stock'] ?? 0,
              barcode: item['barcode'],
              imagePath: finalImagePath,
              variants: item['variants'] != null
                  ? (item['variants'] as List)
                      .map((v) => ProductVariant.fromMap(v))
                      .toList()
                  : (local?.variants ?? const []),
              createdAt: item['created_at'] != null ? DateTime.parse(item['created_at']) : DateTime.now(),
            );
            if (local == null) {
              await DatabaseHelper.instance.createProduct(p);
            } else {
              await DatabaseHelper.instance.updateProduct(p);
            }
          }
        }
      } catch (e) {
        debugPrint('Online product fetch error: $e');
      }
    }

    // 2. Read from SQLite (reliable local cache)
    _products = await DatabaseHelper.instance.readAllProducts(userId: _userId!);

    _isLoading = false;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  Future<void> addProduct(Product product) async {
    await DatabaseHelper.instance.createProduct(product);

    if (ApiService.instance.isAuthenticated) {
      try {
        final res = await ApiService.instance.createProduct(
          name: product.name,
          price: product.price,
          stock: product.stock,
          category: product.category,
          barcode: product.barcode,
          imageFilePath: product.imagePath,
        );
        if (res['product'] != null) {
          final serverProd = res['product'];
          final serverId = serverProd['id'] as int?;
          final serverImagePath = serverProd['image_path']?.toString().trim();
          if (serverId != null) {
            await DatabaseHelper.instance.updateProduct(
              product.copyWith(
                id: serverId,
                imagePath: (serverImagePath != null && serverImagePath.isNotEmpty)
                    ? serverImagePath
                    : product.imagePath,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Online add product error: $e');
      }
    }

    await fetchProducts();
  }

  Future<void> updateProduct(Product product) async {
    await DatabaseHelper.instance.updateProduct(product);

    if (product.id != null && ApiService.instance.isAuthenticated) {
      try {
        final res = await ApiService.instance.updateProduct(
          product.id!,
          name: product.name,
          price: product.price,
          stock: product.stock,
          category: product.category,
          barcode: product.barcode,
          imageFilePath: product.imagePath,
        );
        if (res['product'] != null && res['product']['image_path'] != null) {
          final serverImagePath = res['product']['image_path'].toString().trim();
          if (serverImagePath.isNotEmpty) {
            await DatabaseHelper.instance.updateProduct(
              product.copyWith(imagePath: serverImagePath),
            );
          }
        }
      } catch (e) {
        debugPrint('Online update product error: $e');
      }
    }

    await fetchProducts();
  }

  Future<void> deleteProduct(int id) async {
    await DatabaseHelper.instance.deleteProduct(id);

    if (ApiService.instance.isAuthenticated) {
      try {
        await ApiService.instance.deleteProduct(id);
      } catch (e) {
        debugPrint('Online delete product error: $e');
      }
    }

    await fetchProducts();
  }

  List<Product> get lowStockProducts {
    return _products.where((p) => p.stock <= 5).toList();
  }

  void clearData() {
    _products = [];
    _userId = null;
    _selectedCategory = 'All';
    _searchQuery = '';
    notifyListeners();
  }
}
