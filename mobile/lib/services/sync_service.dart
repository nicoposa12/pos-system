import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../data/database_helper.dart';
import '../models/product.dart';
import 'api_service.dart';

class SyncService {
  static final SyncService instance = SyncService._init();

  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  final ValueNotifier<int> pendingSyncCount = ValueNotifier<int>(0);
  final ValueNotifier<DateTime?> lastSyncedAt = ValueNotifier<DateTime?>(null);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  SyncService._init();

  void init(int? currentUserId) {
    _checkInitialConnectivity();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      isOnline.value = online;
      debugPrint('[SyncService] Connectivity changed: online=$online');

      if (online && currentUserId != null) {
        // Trigger auto-sync when connection is restored
        syncNow(currentUserId);
      }
    });

    if (currentUserId != null) {
      updatePendingCount(currentUserId);
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }

  Future<void> _checkInitialConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    isOnline.value = results.any((r) => r != ConnectivityResult.none);
  }

  Future<void> updatePendingCount(int userId) async {
    try {
      final pending = await DatabaseHelper.instance.getUnsyncedTransactions(userId: userId);
      pendingSyncCount.value = pending.length;
    } catch (_) {}
  }

  /// Manually or automatically trigger bidirectional synchronization
  Future<bool> syncNow(int userId) async {
    if (isSyncing.value) return false;
    if (!ApiService.instance.isAuthenticated) return false;

    isSyncing.value = true;
    try {
      // 1. Sync pending offline transactions up to the cloud
      final pending = await DatabaseHelper.instance.getUnsyncedTransactions(userId: userId);
      if (pending.isNotEmpty) {
        final syncedResults = await ApiService.instance.syncOfflineTransactions(pending);
        final syncedClientIds = syncedResults
            .map<int>((s) => int.parse(s['client_id'].toString()))
            .toList();

        await DatabaseHelper.instance.markTransactionsSynced(syncedClientIds);
        debugPrint('[SyncService] Synced ${syncedClientIds.length} offline transactions to cloud.');
      }

      // 2. Fetch latest product catalog from cloud and cache in local SQLite
      final remoteProducts = await ApiService.instance.getProducts();
      if (remoteProducts.isNotEmpty) {
        for (var p in remoteProducts) {
          final remoteId = p['id'] as int;
          final existing = await DatabaseHelper.instance.readProduct(remoteId);
          final remoteImagePath = p['image_path'] as String?;
          final String? finalImagePath = (remoteImagePath != null && remoteImagePath.trim().isNotEmpty)
              ? remoteImagePath.trim()
              : existing?.imagePath;

          final prod = Product(
            id: remoteId,
            userId: userId,
            name: p['name'] ?? '',
            category: p['category'],
            price: (p['price'] as num?)?.toDouble() ?? 0.0,
            stock: p['stock'] ?? 0,
            barcode: p['barcode'],
            imagePath: finalImagePath,
            createdAt: p['created_at'] != null ? DateTime.parse(p['created_at']) : DateTime.now(),
          );

          if (existing == null) {
            await DatabaseHelper.instance.createProduct(prod);
          } else {
            await DatabaseHelper.instance.updateProduct(prod);
          }
        }
      }

      await updatePendingCount(userId);
      lastSyncedAt.value = DateTime.now();
      isSyncing.value = false;
      return true;
    } catch (e) {
      debugPrint('[SyncService] Sync error: $e');
      isSyncing.value = false;
      return false;
    }
  }
}

