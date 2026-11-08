import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/api_service.dart';

/// Aggregated store telemetry for a single client business or admin account.
class StoreMetrics {
  final int productsCount;
  final int transactionsCount;
  final int debtsCount;
  final double totalSales;
  final bool hasPin;

  const StoreMetrics({
    this.productsCount = 0,
    this.transactionsCount = 0,
    this.debtsCount = 0,
    this.totalSales = 0.0,
    this.hasPin = false,
  });

  factory StoreMetrics.fromJson(
    Map<String, dynamic> stats, {
    bool hasPin = false,
  }) {
    return StoreMetrics(
      productsCount: (stats['products_count'] as num?)?.toInt() ?? 0,
      transactionsCount: (stats['transactions_count'] as num?)?.toInt() ?? 0,
      debtsCount: (stats['debts_count'] as num?)?.toInt() ?? 0,
      totalSales: (stats['total_sales'] as num?)?.toDouble() ?? 0.0,
      hasPin: hasPin,
    );
  }
}

/// Shared state controller for the Executive Admin Console.
/// Uses the cloud API as the sole source of truth and holds telemetry in memory.
class AdminStoreController extends ChangeNotifier {
  List<User> _users = [];
  Map<int, StoreMetrics> _metrics = {};
  bool _isLoading = true;
  bool _isCloudSynced = false;
  DateTime? _lastSyncedAt;
  String? _syncBannerMessage;

  // Network-level summary overrides from backend summary payload
  double _networkSales = 0.0;
  int _networkProducts = 0;
  Timer? _realtimeTimer;
  DateTime _lastActivity = DateTime.now();
  int _idleTicks = 0;

  AdminStoreController({
    List<User>? seedUsers,
    Map<int, StoreMetrics>? seedMetrics,
    bool skipInitialRefresh = false,
  }) {
    if (seedUsers != null) {
      _users = List.of(seedUsers);
      _metrics = seedMetrics != null ? Map.of(seedMetrics) : {};
      _recomputeSummaryFromMetrics();
      _isLoading = false;
      _isCloudSynced = true;
      _lastSyncedAt = DateTime.now();
    }

    ApiService.instance.isOnline.addListener(_onNetworkOnlineChanged);

    if (!skipInitialRefresh) {
      refresh();
      startRealtimePolling();
    }
  }

  void _onNetworkOnlineChanged() {
    if (ApiService.instance.isOnline.value) {
      debugPrint(
        '[AdminStoreController] Connectivity online: refreshing live store telemetry...',
      );
      refresh(silent: true);
    }
  }

  void recordActivity() {
    _lastActivity = DateTime.now();
    _idleTicks = 0;
    if (_realtimeTimer == null) {
      startRealtimePolling();
    }
  }

  void startRealtimePolling() {
    _realtimeTimer?.cancel();
    // Silently fetch store metrics every 25 seconds for executive dashboard
    _realtimeTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      final idleMins = DateTime.now().difference(_lastActivity).inMinutes;
      if (idleMins >= 15) {
        stopRealtimePolling();
        return;
      }
      if (idleMins >= 3) {
        _idleTicks = (_idleTicks + 1) % 3;
        if (_idleTicks != 0) return;
      } else {
        _idleTicks = 0;
      }

      if (ApiService.instance.isAuthenticated) {
        refresh(silent: true);
      }
    });
  }

  void stopRealtimePolling() {
    _realtimeTimer?.cancel();
    _realtimeTimer = null;
  }

  @override
  void dispose() {
    ApiService.instance.isOnline.removeListener(_onNetworkOnlineChanged);
    stopRealtimePolling();
    super.dispose();
  }

  List<User> get users => List.unmodifiable(_users);
  bool get isLoading => _isLoading;
  bool get isCloudSynced => _isCloudSynced;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get syncBannerMessage => _syncBannerMessage;

  List<User> get clientStores => _users.where((u) => !u.isAdmin).toList();
  List<User> get adminUsers => _users.where((u) => u.isAdmin).toList();

  int get totalStoresCount => clientStores.length;
  int get activeStoresCount => clientStores.where((u) => u.isActive).length;
  int get suspendedStoresCount => clientStores.where((u) => !u.isActive).length;
  int get adminsCount => adminUsers.length;

  double get totalNetworkSales => _networkSales;
  int get totalNetworkProducts => _networkProducts;

  int get totalNetworkOrders {
    int sum = 0;
    for (final u in clientStores) {
      if (u.id != null) {
        sum += (_metrics[u.id!]?.transactionsCount ?? 0);
      }
    }
    return sum;
  }

  int get totalUnpaidDebts {
    int sum = 0;
    for (final u in clientStores) {
      if (u.id != null) {
        sum += (_metrics[u.id!]?.debtsCount ?? 0);
      }
    }
    return sum;
  }

  StoreMetrics metricsFor(User user) {
    if (user.id == null) {
      return StoreMetrics(hasPin: user.hasPin);
    }
    return _metrics[user.id!] ?? StoreMetrics(hasPin: user.hasPin);
  }

  /// Client businesses ranked by lifetime sales descending.
  List<User> get topPerformingStores {
    final stores = List<User>.of(clientStores);
    stores.sort((a, b) {
      final salesB = metricsFor(b).totalSales;
      final salesA = metricsFor(a).totalSales;
      final cmp = salesB.compareTo(salesA);
      if (cmp != 0) return cmp;
      return b.createdAt.compareTo(a.createdAt);
    });
    return stores;
  }

  /// Stores that require admin attention (suspended, missing quick PIN, or unpaid debts).
  List<User> get storesNeedingAttention {
    return clientStores.where((u) {
      final m = metricsFor(u);
      return !u.isActive || !m.hasPin || m.debtsCount > 0;
    }).toList();
  }

  void _recomputeSummaryFromMetrics() {
    double sales = 0.0;
    int products = 0;
    for (final u in _users) {
      if (u.id != null && _metrics.containsKey(u.id!)) {
        sales += _metrics[u.id!]!.totalSales;
        products += _metrics[u.id!]!.productsCount;
      }
    }
    _networkSales = sales;
    _networkProducts = products;
  }

  /// Syncs client directory and store KPIs from Neon Cloud API.
  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final onlineData = await ApiService.instance.getAdminClients();
      final rawClients = onlineData['clients'];
      if (rawClients is List) {
        final List<User> cloudUsers = [];
        final Map<int, StoreMetrics> cloudMetrics = {};

        for (final raw in rawClients) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          final cloudUser = User.fromJson(item);
          cloudUsers.add(cloudUser);

          if (cloudUser.id != null) {
            final statsRaw = item['stats'] is Map
                ? Map<String, dynamic>.from(item['stats'] as Map)
                : const <String, dynamic>{};
            cloudMetrics[cloudUser.id!] = StoreMetrics.fromJson(
              statsRaw,
              hasPin: cloudUser.hasPin,
            );
          }
        }

        final summary = onlineData['summary'] is Map
            ? Map<String, dynamic>.from(onlineData['summary'] as Map)
            : const <String, dynamic>{};

        _users = cloudUsers;
        _metrics = cloudMetrics;
        _networkSales = (summary['total_network_sales'] as num?)?.toDouble() ??
            cloudMetrics.values.fold(0.0, (acc, m) => acc + m.totalSales);
        _networkProducts =
            (summary['total_network_products'] as num?)?.toInt() ??
                cloudMetrics.values.fold(0, (acc, m) => acc + m.productsCount);
        _isCloudSynced = true;
        _syncBannerMessage = null;
        _lastSyncedAt = DateTime.now();
      }
    } catch (e) {
      debugPrint('[AdminStoreController] Cloud fetch error: $e');
      _isCloudSynced = false;
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        if (statusCode == 401 || statusCode == 403) {
          _syncBannerMessage =
              'Admin authentication required. Please sign in again.';
        } else if (ApiService.isConnectionError(e)) {
          _syncBannerMessage =
              'Cannot reach cloud server. Please check your internet connection.';
        } else {
          _syncBannerMessage = 'Server error (${statusCode ?? "offline"}).';
        }
      } else {
        _syncBannerMessage = ApiService.describeError(e);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetches live store breakdown (today's sales + 10 recent transactions) from Cloud.
  Future<Map<String, dynamic>?> fetchStoreLiveDetails(int userId) async {
    try {
      final res = await ApiService.instance.getAdminClientDetails(userId);
      if (res['user'] is Map) {
        return Map<String, dynamic>.from(res['user'] as Map);
      }
    } catch (e) {
      debugPrint('[AdminStoreController] Live store detail fetch failed: $e');
    }
    return null;
  }

  /// Creates a new client store or platform administrator account.
  Future<String?> createAccount({
    required String username,
    required String fullName,
    required String password,
    String? email,
    String? pin,
    String? imageFilePath,
    String role = 'client',
  }) async {
    try {
      await ApiService.instance.createAdminClient(
        username: username,
        fullName: fullName,
        password: password,
        email: email,
        pin: pin,
        role: role,
        isActive: true,
        imageFilePath: imageFilePath,
      );

      await refresh(silent: true);
      return null;
    } catch (e) {
      return ApiService.describeError(e, 'Failed to create account.');
    }
  }

  /// Updates business name, email, role, and store photo.
  Future<String?> updateAccount(
    User user, {
    required String fullName,
    String? email,
    required String role,
    String? imageFilePath,
    bool removeImage = false,
  }) async {
    if (user.id == null) return 'Invalid account ID.';
    try {
      await ApiService.instance.updateAdminClient(
        user.id!,
        fullName: fullName,
        email: email,
        role: role,
        imageFilePath: imageFilePath,
        removeImage: removeImage,
      );

      await refresh(silent: true);
      return null;
    } catch (e) {
      return ApiService.describeError(e, 'Failed to update store details.');
    }
  }

  /// Toggles active/suspended access for a store account.
  Future<String?> toggleStatus(User user) async {
    if (user.id == null) return 'Invalid account ID.';
    try {
      await ApiService.instance.toggleClientStatus(user.id!);
      await refresh(silent: true);
      return null;
    } catch (e) {
      return ApiService.describeError(e, 'Failed to update store access status.');
    }
  }

  /// Resets password and/or quick PIN for a store account.
  Future<String?> resetCredentials(
    User user, {
    String? password,
    String? pin,
  }) async {
    if (user.id == null) return 'Invalid account ID.';
    try {
      await ApiService.instance.resetClientCredentials(
        user.id!,
        password: (password != null && password.isNotEmpty) ? password : null,
        pin: (pin != null && pin.isNotEmpty) ? pin : null,
      );

      await refresh(silent: true);
      return null;
    } catch (e) {
      return ApiService.describeError(e, 'Failed to reset credentials.');
    }
  }

  /// Permanently removes a store account and all its cloud records.
  Future<String?> deleteAccount(User user) async {
    if (user.id == null) return 'Invalid account ID.';
    try {
      await ApiService.instance.deleteAdminClient(user.id!);
      await refresh(silent: true);
      return null;
    } catch (e) {
      return ApiService.describeError(e, 'Failed to delete store account.');
    }
  }
}
