import 'dart:convert';
import 'package:flutter/material.dart';
import '../data/database_helper.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';

class ProductProvider with ChangeNotifier {
  List<Product> _products = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String _selectedCategory = 'All';
  int? _userId;

  ProductProvider() {
    SyncService.instance.addProductUpdateListener(_onRealtimeProductUpdate);
  }

  @override
  void dispose() {
    SyncService.instance.removeProductUpdateListener(_onRealtimeProductUpdate);
    super.dispose();
  }

  void _onRealtimeProductUpdate() {
    if (_userId != null) {
      _reloadFromLocalCache();
    }
  }

  Future<void> _reloadFromLocalCache() async {
    if (_userId == null) return;
    _products = await DatabaseHelper.instance.readAllProducts(userId: _userId!);
    notifyListeners();
  }

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

  Future<void> fetchProducts({bool silent = false}) async {
    if (_userId == null) return;

    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    // 1. Try fetching from Cloud API if authenticated
    if (ApiService.instance.isAuthenticated) {
      try {
        final remote = await ApiService.instance.getProducts();
        if (remote.isNotEmpty) {
          final Set<int> remoteIds = {};
          for (var item in remote) {
            final remoteId = item['id'] as int;
            remoteIds.add(remoteId);
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
              isSynced: true,
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

          // Clean up any stale local orphan duplicates in SQLite that don't exist on server (only if previously synced)
          final localProducts = await DatabaseHelper.instance.readAllProducts(userId: _userId!);
          for (var lp in localProducts) {
            if (lp.id != null && lp.isSynced && !remoteIds.contains(lp.id)) {
              await DatabaseHelper.instance.deleteProduct(lp.id!);
            }
          }
        }
      } catch (e) {
        debugPrint('Online product fetch error: $e');
      }
    }

    // 2. Read from SQLite (reliable local cache)
    _products = await DatabaseHelper.instance.readAllProducts(userId: _userId!);

    if (!silent) {
      _isLoading = false;
    }
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

  /// Returns `true` when the product was saved to the cloud (Neon),
  /// `false` when it was saved locally only and queued for background sync.
  Future<bool> addProduct(Product product) async {
    if (_userId == null && product.userId > 0) {
      _userId = product.userId;
    }

    // 1. If online, create on server first to get authoritative server ID and prevent local duplicates
    if (ApiService.instance.isAuthenticated) {
      try {
        final res = await ApiService.instance.createProduct(
          name: product.name,
          price: product.price,
          stock: product.stock,
          category: product.category,
          barcode: product.barcode,
          variants: product.variants.isNotEmpty
              ? jsonEncode(product.variants.map((v) => v.toMap()).toList())
              : null,
          imageFilePath: product.imagePath,
        );
        if (res['product'] != null) {
          final serverProd = res['product'];
          final serverId = serverProd['id'] as int?;
          final serverImagePath = serverProd['image_path']?.toString().trim();
          final serverProduct = product.copyWith(
            id: serverId,
            isSynced: true,
            imagePath: (serverImagePath != null && serverImagePath.isNotEmpty)
                ? serverImagePath
                : product.imagePath,
          );
          await DatabaseHelper.instance.createProduct(serverProduct);
          await fetchProducts();
          return true;
        }
      } catch (e) {
        debugPrint('Online add product error: $e');
      }
    }

    // 2. Offline fallback: save locally with isSynced = false if disconnected or server request failed
    final localProduct = product.copyWith(isSynced: false);
    await DatabaseHelper.instance.createProduct(localProduct);
    await fetchProducts();

    // 3. Trigger background sync so pending product uploads to cloud as soon as reachable
    final targetUserId = _userId ?? (product.userId > 0 ? product.userId : null);
    if (targetUserId != null && ApiService.instance.isAuthenticated) {
      SyncService.instance.syncNow(targetUserId);
    }
    return false;
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
          variants: product.variants.isNotEmpty
              ? jsonEncode(product.variants.map((v) => v.toMap()).toList())
              : null,
          imageFilePath: product.imagePath,
        );
        if (res['product'] != null && res['product']['image_path'] != null) {
          final serverImagePath = res['product']['image_path'].toString().trim();
          if (serverImagePath.isNotEmpty) {
            await DatabaseHelper.instance.updateProduct(
              product.copyWith(imagePath: serverImagePath, isSynced: true),
            );
          } else {
            await DatabaseHelper.instance.updateProduct(
              product.copyWith(isSynced: true),
            );
          }
        } else {
          await DatabaseHelper.instance.updateProduct(
            product.copyWith(isSynced: true),
          );
        }
      } catch (e) {
        debugPrint('Online update product error: $e');
      }
    } else {
      // Offline edit: mark as unsynced so next sync pushes changes
      await DatabaseHelper.instance.updateProduct(
        product.copyWith(isSynced: false),
      );
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
