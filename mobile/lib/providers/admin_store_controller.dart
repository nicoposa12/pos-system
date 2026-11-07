import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../data/database_helper.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';

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
/// Uses Neon PostgreSQL (via Laravel API) as the primary source of truth
/// and gracefully falls back to local SQLite cache when offline.
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

    SyncService.instance.isOnline.addListener(_onNetworkOnlineChanged);

    if (!skipInitialRefresh) {
      refresh();
      startRealtimePolling();
    }
  }

  void _onNetworkOnlineChanged() {
    if (SyncService.instance.isOnline.value) {
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
    // Silently fetch store metrics every 25 seconds for executive dashboard (free-tier optimized)
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
    SyncService.instance.isOnline.removeListener(_onNetworkOnlineChanged);
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
      return StoreMetrics(hasPin: user.pin != null && user.pin!.isNotEmpty);
    }
    return _metrics[user.id!] ??
        StoreMetrics(hasPin: user.pin != null && user.pin!.isNotEmpty);
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

  bool _isConnectionFailure(Object error) {
    if (error is DioException) {
      return error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.response == null;
    }
    return false;
  }

  String _extractErrorMessage(Object error, String fallback) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        if (data['errors'] is Map) {
          final errorsMap = data['errors'] as Map;
          for (final entry in errorsMap.values) {
            if (entry is List && entry.isNotEmpty) {
              return entry.first.toString();
            }
          }
        }
        if (data['message'] != null &&
            data['message'].toString().trim().isNotEmpty) {
          return data['message'].toString();
        }
      }
      if (_isConnectionFailure(error)) {
        return 'Cannot reach cloud server. Please check your internet connection.';
      }
    }
    return fallback;
  }

  /// Syncs client directory and store KPIs from Neon Cloud, falling back to local SQLite.
  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      await DatabaseHelper.instance.ensureDefaultAdmin();

      // 1. Primary path: Live Neon PostgreSQL via Backend API
      try {
        final onlineData = await ApiService.instance.getAdminClients();
        final rawClients = onlineData['clients'];
        if (rawClients is List) {
          final List<User> cloudUsers = [];
          final Map<int, StoreMetrics> cloudMetrics = {};
          final Set<String> cloudUsernames = {};

          for (final raw in rawClients) {
            if (raw is! Map) continue;
            final item = Map<String, dynamic>.from(raw);
            final username = (item['username'] ?? '').toString();
            if (username.isEmpty) continue;
            cloudUsernames.add(username.toLowerCase());

            final localMatch = await DatabaseHelper.instance.getUser(username);
            final id = (item['id'] as num?)?.toInt();
            final hasPin =
                item['has_pin'] == true ||
                (localMatch?.pin != null && localMatch!.pin!.isNotEmpty);

            final cloudUser = User(
              id: id ?? localMatch?.id,
              username: username,
              password: localMatch?.password ?? '',
              pin: localMatch?.pin,
              fullName: (item['full_name'] ?? username).toString(),
              email: item['email']?.toString(),
              imagePath: item['image_path']?.toString() ?? localMatch?.imagePath,
              role: (item['role'] ?? 'client').toString(),
              isActive: item['is_active'] != false,
              createdAt: item['created_at'] != null
                  ? DateTime.tryParse(item['created_at'].toString()) ??
                        DateTime.now()
                  : (localMatch?.createdAt ?? DateTime.now()),
            );
            cloudUsers.add(cloudUser);

            if (cloudUser.id != null) {
              final statsRaw = item['stats'] is Map
                  ? Map<String, dynamic>.from(item['stats'] as Map)
                  : const <String, dynamic>{};
              cloudMetrics[cloudUser.id!] = StoreMetrics.fromJson(
                statsRaw,
                hasPin: hasPin,
              );
            }
          }

          final summary = onlineData['summary'] is Map
              ? Map<String, dynamic>.from(onlineData['summary'] as Map)
              : const <String, dynamic>{};

          // 2. Commit Live Cloud state to UI immediately
          _users = cloudUsers;
          _metrics = cloudMetrics;
          _networkSales =
              (summary['total_network_sales'] as num?)?.toDouble() ??
              cloudMetrics.values.fold(0.0, (acc, m) => acc + m.totalSales);
          _networkProducts =
              (summary['total_network_products'] as num?)?.toInt() ??
              cloudMetrics.values.fold(0, (acc, m) => acc + m.productsCount);
          _isCloudSynced = true;
          _syncBannerMessage = null;
          _lastSyncedAt = DateTime.now();
          SyncService.instance.isOnline.value = true;
          _isLoading = false;
          notifyListeners();

          // 3. Persist local SQLite cache mirror in background (isolated from cloud sync state)
          unawaited(_persistLocalMirror(cloudUsers, cloudUsernames));
          return;
        }
      } catch (e) {
        debugPrint(
          '[AdminStoreController] Cloud fetch unavailable, using SQLite cache: $e',
        );
        _isCloudSynced = false;
        if (e is DioException) {
          final statusCode = e.response?.statusCode;
          if (statusCode == 401 || statusCode == 403) {
            _syncBannerMessage =
                'Admin authentication required. Please sign in again.';
          } else if (_isConnectionFailure(e)) {
            _syncBannerMessage =
                'Cannot reach cloud server. Showing offline cache.';
          } else {
            _syncBannerMessage =
                'Cloud unavailable (${statusCode ?? "error"}). Showing offline cache.';
          }
        } else {
          _syncBannerMessage =
              'Showing offline cache — connect to internet to sync live store telemetry.';
        }
      }

      // 2. Offline Fallback: Local SQLite cache
      final allLocal = await DatabaseHelper.instance.getAllUsers();
      final Map<int, StoreMetrics> localMetrics = {};
      for (final u in allLocal) {
        if (u.id != null) {
          final stats = await DatabaseHelper.instance.getUserStats(u.id!);
          localMetrics[u.id!] = StoreMetrics.fromJson(
            stats,
            hasPin: u.pin != null && u.pin!.isNotEmpty,
          );
        }
      }

      _users = allLocal;
      _metrics = localMetrics;
      _recomputeSummaryFromMetrics();
    } catch (e) {
      debugPrint('[AdminStoreController] Unexpected refresh error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _persistLocalMirror(
    List<User> cloudUsers,
    Set<String> cloudUsernames,
  ) async {
    try {
      for (final cloudUser in cloudUsers) {
        final localMatch = await DatabaseHelper.instance.getUser(
          cloudUser.username,
        );
        if (localMatch != null) {
          await DatabaseHelper.instance.updateUser(
            localMatch.copyWith(
              fullName: cloudUser.fullName,
              email: cloudUser.email,
              imagePath: cloudUser.imagePath,
              role: cloudUser.role,
              isActive: cloudUser.isActive,
            ),
          );
        } else {
          try {
            await DatabaseHelper.instance.createUser(
              cloudUser.copyWith(id: null),
            );
          } catch (_) {}
        }
      }

      // Prune stale cached client accounts that were deleted from Neon
      final localUsers = await DatabaseHelper.instance.getAllUsers();
      for (final local in localUsers) {
        final uname = local.username.toLowerCase();
        if (uname != 'admin' &&
            !cloudUsernames.contains(uname) &&
            local.id != null) {
          try {
            await DatabaseHelper.instance.deleteUser(local.id!);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint(
        '[AdminStoreController] Warning: SQLite local cache mirror non-fatal error: $e',
      );
    }
  }

  /// Fetches live store breakdown (today's sales + 10 recent transactions) from Neon.
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
  /// Returns `null` on success, or an error string on failure.
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
      final res = await ApiService.instance.createAdminClient(
        username: username,
        fullName: fullName,
        password: password,
        email: email,
        pin: pin,
        role: role,
        isActive: true,
        imageFilePath: imageFilePath,
      );

      final createdUser = res['user'] is Map ? Map<String, dynamic>.from(res['user'] as Map) : null;
      final savedImagePath = createdUser?['image_path']?.toString() ?? imageFilePath;

      // Mirror locally for instant offline resilience
      final existingLocal = await DatabaseHelper.instance.getUser(username);
      if (existingLocal == null) {
        await DatabaseHelper.instance.createUser(
          User(
            username: username,
            password: password,
            fullName: fullName,
            email: email,
            pin: pin,
            imagePath: savedImagePath,
            role: role,
            isActive: true,
            createdAt: DateTime.now(),
          ),
        );
      }

      await refresh(silent: true);
      return null;
    } catch (e) {
      if (_isConnectionFailure(e)) {
        return 'Offline: Connect to the internet to provision @$username in Neon Cloud.';
      }
      return _extractErrorMessage(e, 'Failed to create account.');
    }
  }

  /// Updates business name, email, role, and store photo. Returns `null` on success.
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
      final res = await ApiService.instance.updateAdminClient(
        user.id!,
        fullName: fullName,
        email: email,
        role: role,
        imageFilePath: imageFilePath,
        removeImage: removeImage,
      );

      final updatedData = res['user'] is Map ? Map<String, dynamic>.from(res['user'] as Map) : null;
      final updatedImagePath = removeImage
          ? null
          : (updatedData?['image_path']?.toString() ?? imageFilePath ?? user.imagePath);

      final local = await DatabaseHelper.instance.getUser(user.username);
      if (local != null) {
        await DatabaseHelper.instance.updateUser(
          local.copyWith(
            fullName: fullName,
            email: email,
            role: role,
            imagePath: updatedImagePath,
          ),
        );
      }

      await refresh(silent: true);
      return null;
    } catch (e) {
      return _extractErrorMessage(e, 'Failed to update store details.');
    }
  }

  /// Toggles active/suspended access for a store account. Returns `null` on success.
  Future<String?> toggleStatus(User user) async {
    if (user.id == null) return 'Invalid account ID.';
    final targetState = !user.isActive;
    try {
      await ApiService.instance.toggleClientStatus(user.id!);

      final local = await DatabaseHelper.instance.getUser(user.username);
      if (local?.id != null) {
        await DatabaseHelper.instance.updateUserStatus(local!.id!, targetState);
      }

      await refresh(silent: true);
      return null;
    } catch (e) {
      return _extractErrorMessage(e, 'Failed to update store access status.');
    }
  }

  /// Resets password and/or quick PIN for a store account. Returns `null` on success.
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

      final local = await DatabaseHelper.instance.getUser(user.username);
      if (local?.id != null) {
        await DatabaseHelper.instance.updateUserCredentials(
          local!.id!,
          password: (password != null && password.isNotEmpty) ? password : null,
          pin: (pin != null && pin.isNotEmpty) ? pin : null,
        );
      }

      await refresh(silent: true);
      return null;
    } catch (e) {
      return _extractErrorMessage(e, 'Failed to reset credentials.');
    }
  }

  /// Permanently removes a store account and all its cloud + local records.
  /// Returns `null` on success.
  Future<String?> deleteAccount(User user) async {
    if (user.id == null) return 'Invalid account ID.';
    try {
      await ApiService.instance.deleteAdminClient(user.id!);

      final local = await DatabaseHelper.instance.getUser(user.username);
      if (local?.id != null) {
        await DatabaseHelper.instance.deleteUser(local!.id!);
      }

      await refresh(silent: true);
      return null;
    } catch (e) {
      return _extractErrorMessage(e, 'Failed to delete store account.');
    }
  }
}
