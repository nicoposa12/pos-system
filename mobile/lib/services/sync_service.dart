import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import '../data/database_helper.dart';
import '../models/product.dart';
import 'api_service.dart';

class SyncService with WidgetsBindingObserver {
  static final SyncService instance = SyncService._init();

  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  final ValueNotifier<int> pendingSyncCount = ValueNotifier<int>(0);
  final ValueNotifier<DateTime?> lastSyncedAt = ValueNotifier<DateTime?>(null);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _realtimeTimer;
  int? _currentUserId;
  String? _lastProductVersion;
  String? _lastTxVersion;
  String? _lastDebtVersion;
  bool _isCheckingRealtime = false;

  final Set<VoidCallback> _productUpdateListeners = {};
  final Set<VoidCallback> _transactionUpdateListeners = {};

  SyncService._init() {
    WidgetsBinding.instance.addObserver(this);
  }

  void addProductUpdateListener(VoidCallback listener) => _productUpdateListeners.add(listener);
  void removeProductUpdateListener(VoidCallback listener) => _productUpdateListeners.remove(listener);

  void addTransactionUpdateListener(VoidCallback listener) => _transactionUpdateListeners.add(listener);
  void removeTransactionUpdateListener(VoidCallback listener) => _transactionUpdateListeners.remove(listener);

  void notifyProductUpdate() {
    for (final listener in List.of(_productUpdateListeners)) {
      try {
        listener();
      } catch (e) {
        debugPrint('[SyncService] Error notifying product listener: $e');
      }
    }
  }

  void notifyTransactionUpdate() {
    for (final listener in List.of(_transactionUpdateListeners)) {
      try {
        listener();
      } catch (e) {
        debugPrint('[SyncService] Error notifying transaction listener: $e');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkRealtimeUpdates();
      startRealtimePolling();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      stopRealtimePolling();
    }
  }

  void init(int? currentUserId) {
    _currentUserId = currentUserId;
    _checkInitialConnectivity();

    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      isOnline.value = online;
      debugPrint('[SyncService] Connectivity changed: online=$online');

      if (online && _currentUserId != null) {
        syncNow(_currentUserId!);
      }
    });

    if (currentUserId != null) {
      updatePendingCount(currentUserId);
      if (ApiService.instance.isAuthenticated) {
        syncNow(currentUserId);
      }
      startRealtimePolling();
    } else {
      stopRealtimePolling();
    }
  }

  void startRealtimePolling() {
    _realtimeTimer?.cancel();
    if (_currentUserId == null) return;
    // Poll fast status hashes every 5 seconds for sub-second reactive updates
    _realtimeTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      checkRealtimeUpdates();
    });
  }

  void stopRealtimePolling() {
    _realtimeTimer?.cancel();
    _realtimeTimer = null;
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    stopRealtimePolling();
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

  /// Fast change-detection polling: checks server entity hashes.
  /// If changes occurred on cloud or another terminal, silently fetches deltas
  /// and updates SQLite without swipe-to-refresh or user disruption.
  Future<void> checkRealtimeUpdates() async {
    if (_isCheckingRealtime || isSyncing.value || !isOnline.value) return;
    if (!ApiService.instance.isAuthenticated || _currentUserId == null) return;

    _isCheckingRealtime = true;
    try {
      final status = await ApiService.instance.getSyncStatus();
      if (status == null) {
        _isCheckingRealtime = false;
        return;
      }

      final prodVersion = status['products_version']?.toString();
      final txVersion = status['transactions_version']?.toString();
      final debtVersion = status['debts_version']?.toString();

      bool didProductChange = false;
      bool didTxChange = false;

      // 1. Remote Products changed
      if (prodVersion != null && prodVersion != _lastProductVersion) {
        _lastProductVersion = prodVersion;
        await _pullRemoteProducts(_currentUserId!);
        didProductChange = true;
      }

      // 2. Remote Transactions or Debts changed
      if ((txVersion != null && txVersion != _lastTxVersion) ||
          (debtVersion != null && debtVersion != _lastDebtVersion)) {
        _lastTxVersion = txVersion;
        _lastDebtVersion = debtVersion;
        await _pullRemoteTransactions(_currentUserId!);
        didTxChange = true;
      }

      // 3. Push any locally queued offline transactions if network is online
      final pending = await DatabaseHelper.instance.getUnsyncedTransactions(userId: _currentUserId!);
      if (pending.isNotEmpty) {
        await _pushPendingTransactions(_currentUserId!);
        didTxChange = true;
      }

      await updatePendingCount(_currentUserId!);
      lastSyncedAt.value = DateTime.now();

      // Broadcast changes to active providers
      if (didProductChange) {
        notifyProductUpdate();
      }
      if (didTxChange) {
        notifyTransactionUpdate();
      }
    } catch (e) {
      debugPrint('[SyncService] checkRealtimeUpdates error: $e');
    } finally {
      _isCheckingRealtime = false;
    }
  }

  /// Manually or automatically trigger full bidirectional synchronization
  Future<bool> syncNow(int userId) async {
    if (isSyncing.value) return false;
    if (!ApiService.instance.isAuthenticated) return false;

    isSyncing.value = true;
    try {
      await _pushPendingTransactions(userId);
      await _pullRemoteProducts(userId);
      await _pullRemoteTransactions(userId);

      await updatePendingCount(userId);
      lastSyncedAt.value = DateTime.now();
      isSyncing.value = false;

      notifyProductUpdate();
      notifyTransactionUpdate();
      return true;
    } catch (e) {
      debugPrint('[SyncService] Sync error: $e');
      isSyncing.value = false;
      return false;
    }
  }

  Future<void> _pushPendingTransactions(int userId) async {
    final pending = await DatabaseHelper.instance.getUnsyncedTransactions(userId: userId);
    if (pending.isEmpty) return;

    final syncedResults = await ApiService.instance.syncOfflineTransactions(pending);
    for (var s in syncedResults) {
      final clientId = int.tryParse(s['client_id']?.toString() ?? '');
      final serverId = int.tryParse(s['server_id']?.toString() ?? '');
      if (clientId != null && serverId != null) {
        await DatabaseHelper.instance.replaceTransactionId(clientId, serverId);
      }
    }
    debugPrint('[SyncService] Synced ${syncedResults.length} offline transactions to cloud.');
  }

  Future<void> _pullRemoteProducts(int userId) async {
    final remoteProducts = await ApiService.instance.getProducts();
    if (remoteProducts.isEmpty) return;

    final Set<int> remoteIds = {};
    for (var p in remoteProducts) {
      final remoteId = p['id'] as int;
      remoteIds.add(remoteId);
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
        variants: p['variants'] != null
            ? (p['variants'] as List)
                .map((v) => ProductVariant.fromMap(v))
                .toList()
            : (existing?.variants ?? const []),
        createdAt: p['created_at'] != null ? DateTime.parse(p['created_at']) : DateTime.now(),
      );

      if (existing == null) {
        await DatabaseHelper.instance.createProduct(prod);
      } else {
        await DatabaseHelper.instance.updateProduct(prod);
      }
    }

    // Clean up any stale local orphan duplicates in SQLite
    final localProducts = await DatabaseHelper.instance.readAllProducts(userId: userId);
    for (var lp in localProducts) {
      if (lp.id != null && !remoteIds.contains(lp.id)) {
        await DatabaseHelper.instance.deleteProduct(lp.id!);
      }
    }
  }

  Future<void> _pullRemoteTransactions(int userId) async {
    final remoteTransactions = await ApiService.instance.getTransactions(all: true);
    if (remoteTransactions.isNotEmpty) {
      await DatabaseHelper.instance.syncTransactionsFromRemote(userId, remoteTransactions);
      debugPrint('[SyncService] Synced ${remoteTransactions.length} remote transactions into local cache.');
    }
  }

  /// Dedicated fast sync for transactions & sales history
  Future<bool> syncTransactions(int userId) async {
    if (!ApiService.instance.isAuthenticated) return false;
    try {
      await _pullRemoteTransactions(userId);
      lastSyncedAt.value = DateTime.now();
      notifyTransactionUpdate();
      return true;
    } catch (e) {
      debugPrint('[SyncService] syncTransactions error: $e');
      return false;
    }
  }
}
