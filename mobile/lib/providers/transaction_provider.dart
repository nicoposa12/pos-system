import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../services/realtime_service.dart';

/// Sales history, loaded from the cloud API and held in memory.
///
/// The first load fetches the full history; later refreshes request only
/// records modified since the newest `updated_at` already held (delta sync).
/// Dashboard aggregates are memoized and recomputed only when data changes.
class TransactionProvider with ChangeNotifier {
  List<SaleTransaction> _transactions = [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  int? _userId;
  String? _cursor; // newest server updated_at held in memory
  Future<void>? _inFlight;

  // Memoized aggregates
  List<Map<String, dynamic>>? _topProductsCache;
  List<Map<String, dynamic>>? _categorySalesCache;
  final Map<String, double> _totalsCache = {};

  TransactionProvider() {
    RealtimeService.instance.addTransactionListener(_onRemoteChange);
  }

  @override
  void dispose() {
    RealtimeService.instance.removeTransactionListener(_onRemoteChange);
    super.dispose();
  }

  void _onRemoteChange() {
    if (_userId != null) fetchTransactions(silent: true);
  }

  List<SaleTransaction> get transactions => _transactions;
  bool get isLoading => _isLoading;

  /// Last load error (e.g. no internet), or `null` when the data is current.
  String? get errorMessage => _errorMessage;

  List<Map<String, dynamic>> get topProducts =>
      _topProductsCache ??= _computeTopProducts();
  List<Map<String, dynamic>> get categorySales =>
      _categorySalesCache ??= _computeCategorySales();

  void setUserId(int? userId) {
    if (_userId != userId) {
      _userId = userId;
      _hasLoaded = false;
      _cursor = null;
      _setTransactions([]);
      fetchTransactions();
    }
  }

  void _setTransactions(List<SaleTransaction> list) {
    _transactions = list;
    _topProductsCache = null;
    _categorySalesCache = null;
    _totalsCache.clear();
    for (final t in list) {
      final u = t.updatedAt;
      if (u != null && (_cursor == null || u.compareTo(_cursor!) > 0)) {
        _cursor = u;
      }
    }
  }

  /// Merges server records into memory (replacing same ids), newest first.
  void _merge(Iterable<SaleTransaction> incoming) {
    final byId = <int, SaleTransaction>{
      for (final t in _transactions)
        if (t.id != null) t.id!: t,
    };
    for (final t in incoming) {
      if (t.id != null) byId[t.id!] = t;
    }
    final merged = byId.values.toList()..sort((a, b) {
      final cmp = b.date.compareTo(a.date);
      if (cmp != 0) return cmp;
      return (b.id ?? 0).compareTo(a.id ?? 0);
    });
    _setTransactions(merged);
  }

  /// Loads sales from the API. Concurrent calls share one request; once loaded,
  /// refreshes are silent and fetch only changed records.
  Future<void> fetchTransactions({bool silent = false}) {
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
    final since = _hasLoaded ? _cursor : null;
    try {
      final remote = await ApiService.instance.getTransactions(all: true, since: since);
      if (requestedFor != _userId) return; // session changed mid-request
      final parsed = remote
          .whereType<Map>()
          .map((t) => SaleTransaction.fromJson(Map<String, dynamic>.from(t)));
      if (since == null) {
        _setTransactions(parsed.toList()..sort((a, b) {
          final cmp = b.date.compareTo(a.date);
          if (cmp != 0) return cmp;
          return (b.id ?? 0).compareTo(a.id ?? 0);
        }));
      } else if (remote.isNotEmpty) {
        _merge(parsed);
      }
      _hasLoaded = true;
      _errorMessage = null;
    } catch (e) {
      debugPrint('[TransactionProvider] fetch error: $e');
      _errorMessage = ApiService.describeError(e, 'Unable to load sales history.');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Adds a just-completed sale returned by the checkout API.
  void addCompletedTransaction(SaleTransaction tx) {
    _merge([tx]);
    notifyListeners();
  }

  double _sumWhere(String key, bool Function(SaleTransaction t) test) {
    return _totalsCache[key] ??= _transactions
        .where(test)
        .fold<double>(0.0, (sum, t) => sum + t.totalAmount);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  double get dailyTotal {
    final today = DateTime.now();
    return _sumWhere('day', (t) => _isSameDay(t.date, today));
  }

  double get weeklyTotal {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    return _sumWhere('week', (t) => t.date.isAfter(weekAgo));
  }

  double get monthlyTotal {
    final today = DateTime.now();
    return _sumWhere(
      'month',
      (t) => t.date.year == today.year && t.date.month == today.month,
    );
  }

  double get yearlyTotal {
    final today = DateTime.now();
    return _sumWhere('year', (t) => t.date.year == today.year);
  }

  // Get sales data for the last 7 days
  Map<String, double> getWeeklySalesData() {
    final now = DateTime.now();
    final Map<String, double> data = {};
    final byDay = <String, double>{};
    for (final t in _transactions) {
      final key = DateTime(t.date.year, t.date.month, t.date.day)
          .toIso8601String()
          .split('T')[0];
      byDay[key] = (byDay[key] ?? 0.0) + t.totalAmount;
    }

    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      // Use a consistent ISO format for the key
      final dayKey = DateTime(date.year, date.month, date.day).toIso8601String().split('T')[0];
      data[dayKey] = byDay[dayKey] ?? 0.0;
    }
    return data;
  }

  int get dailyTransactionCount {
    final today = DateTime.now();
    return _transactions.where((t) => _isSameDay(t.date, today)).length;
  }

  List<Map<String, dynamic>> _computeTopProducts({int limit = 5}) {
    final byProduct = <int, Map<String, dynamic>>{};
    for (final t in _transactions) {
      for (final item in t.items) {
        final id = item['product_id'] as int? ?? 0;
        final entry = byProduct.putIfAbsent(
          id,
          () => {'name': item['product_name'], 'total_sold': 0, 'total_revenue': 0.0},
        );
        entry['total_sold'] = (entry['total_sold'] as int) + (item['quantity'] as int? ?? 0);
        entry['total_revenue'] = (entry['total_revenue'] as double) +
            ((item['subtotal'] as num?)?.toDouble() ?? 0.0);
      }
    }
    final list = byProduct.values.toList()
      ..sort((a, b) => (b['total_sold'] as int).compareTo(a['total_sold'] as int));
    return List.unmodifiable(list.take(limit));
  }

  List<Map<String, dynamic>> _computeCategorySales() {
    final byCategory = <String, double>{};
    for (final t in _transactions) {
      for (final item in t.items) {
        final raw = item['category']?.toString();
        final category = (raw == null || raw.isEmpty) ? 'Uncategorized' : raw;
        byCategory[category] = (byCategory[category] ?? 0.0) +
            ((item['subtotal'] as num?)?.toDouble() ?? 0.0);
      }
    }
    final list = byCategory.entries
        .map((e) => <String, dynamic>{'category': e.key, 'total_revenue': e.value})
        .toList()
      ..sort((a, b) =>
          (b['total_revenue'] as double).compareTo(a['total_revenue'] as double));
    return List.unmodifiable(list);
  }

  /// Line items for a sale: from memory when available, otherwise from the API.
  Future<List<Map<String, dynamic>>> getTransactionItems(int id) async {
    final tx = await findTransaction(id);
    return tx?.items ?? const [];
  }

  /// Finds a sale in memory, falling back to `GET /transactions/{id}`.
  Future<SaleTransaction?> findTransaction(int id) async {
    for (final t in _transactions) {
      if (t.id == id) return t;
    }
    try {
      final tx = SaleTransaction.fromJson(await ApiService.instance.getTransaction(id));
      if (_userId != null && tx.userId == _userId) _merge([tx]);
      return tx;
    } catch (e) {
      debugPrint('[TransactionProvider] transaction $id lookup failed: $e');
      return null;
    }
  }

  /// Product returns recorded for this store (newest first).
  Future<List<Map<String, dynamic>>> fetchReturns() async {
    final raw = await ApiService.instance.getReturns();
    return raw.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList();
  }

  String? _lastActionError;

  /// Readable reason for the last failed [processReturn] / [markTransactionPaid].
  String? get lastActionError => _lastActionError;

  /// Records a return on the server (which restores stock). On success returns
  /// the product's updated stock level; returns `null` on failure.
  Future<int?> processReturn({
    required int transactionId,
    required int productId,
    required int quantity,
    required String reason,
  }) async {
    if (_userId == null) return null;
    _lastActionError = null;

    try {
      final res = await ApiService.instance.createReturn(
        transactionId,
        productId: productId,
        quantity: quantity,
        reason: reason,
      );

      // If backend returned the updated transaction, merge immediately
      if (res['transaction'] is Map) {
        final updatedTx = SaleTransaction.fromJson(
          Map<String, dynamic>.from(res['transaction'] as Map),
        );
        _merge([updatedTx]);
      }

      // Re-fetch transactions to immediately reflect updated quantity and price across all screens
      await fetchTransactions(silent: true);

      return (res['product_stock'] as num?)?.toInt() ?? -1;
    } catch (e) {
      debugPrint('Error processing return: $e');
      _lastActionError = ApiService.describeError(e, 'Failed to process return.');
      return null;
    }
  }

  Future<bool> markTransactionPaid({
    required int transactionId,
    required String newPaymentMethod,
    required double cashReceived,
    required double changeAmount,
  }) async {
    _lastActionError = null;
    try {
      await ApiService.instance.markTransactionPaid(
        transactionId,
        paymentMethod: newPaymentMethod,
        cashReceived: cashReceived,
        changeAmount: changeAmount,
      );
      await fetchTransactions(silent: true);
      return true;
    } catch (e) {
      debugPrint('Error marking transaction paid: $e');
      _lastActionError = ApiService.describeError(e, 'Failed to record payment.');
      return false;
    }
  }

  void clearData() {
    _setTransactions([]);
    _userId = null;
    _hasLoaded = false;
    _cursor = null;
    _errorMessage = null;
    notifyListeners();
  }
}
