import 'dart:async';
import 'package:flutter/widgets.dart';
import 'api_service.dart';

/// Lightweight cross-device change detection for the online-only POS.
///
/// Polls the tiny `/sync/status` hash endpoint and notifies providers only when
/// products or transactions actually changed on the server, so they can refresh
/// their in-memory state. Polling is adaptive to keep Render / Neon free-tier
/// usage low:
/// - Active: every 15s
/// - Idle 3+ min: every 60s
/// - Idle 15+ min or app in background: stopped (server can sleep)
class RealtimeService with WidgetsBindingObserver {
  static final RealtimeService instance = RealtimeService._init();

  static const _tick = Duration(seconds: 15);

  final Set<VoidCallback> _productListeners = {};
  final Set<VoidCallback> _transactionListeners = {};

  Timer? _timer;
  bool _enabled = false;
  bool _isChecking = false;
  String? _productsVersion;
  String? _transactionsVersion;
  String? _debtsVersion;
  DateTime _lastUserActivity = DateTime.now();
  int _idleTickCounter = 0;

  RealtimeService._init() {
    WidgetsBinding.instance.addObserver(this);
  }

  void addProductListener(VoidCallback listener) => _productListeners.add(listener);
  void removeProductListener(VoidCallback listener) => _productListeners.remove(listener);

  void addTransactionListener(VoidCallback listener) => _transactionListeners.add(listener);
  void removeTransactionListener(VoidCallback listener) => _transactionListeners.remove(listener);

  /// Starts change detection for a signed-in store session.
  void start() {
    _enabled = true;
    _productsVersion = null;
    _transactionsVersion = null;
    _debtsVersion = null;
    recordUserActivity();
    _startTimer();
  }

  /// Stops change detection (signed out, locked, or admin session).
  void stop() {
    _enabled = false;
    _stopTimer();
  }

  /// Marks user interaction (tap, navigation, sale) to keep polling active.
  void recordUserActivity() {
    _lastUserActivity = DateTime.now();
    _idleTickCounter = 0;
    if (_enabled && _timer == null) _startTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled) return;
    if (state == AppLifecycleState.resumed) {
      recordUserActivity();
      checkNow();
    } else if (state == AppLifecycleState.paused) {
      _stopTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) {
      final idleMinutes = DateTime.now().difference(_lastUserActivity).inMinutes;
      if (idleMinutes >= 15) {
        _stopTimer();
        return;
      }
      if (idleMinutes >= 3) {
        _idleTickCounter = (_idleTickCounter + 1) % 4;
        if (_idleTickCounter != 0) return;
      }
      checkNow();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Checks server version hashes and notifies listeners of changed entities.
  /// The first check only records a baseline (providers load fresh data on start).
  Future<void> checkNow() async {
    if (!_enabled || _isChecking || !ApiService.instance.isAuthenticated) return;
    _isChecking = true;
    try {
      final status = await ApiService.instance.getSyncStatus();
      if (status == null || !_enabled) return;

      final products = status['products_version']?.toString();
      final transactions = status['transactions_version']?.toString();
      final debts = status['debts_version']?.toString();

      final productsChanged = _productsVersion != null && products != _productsVersion;
      final transactionsChanged =
          (_transactionsVersion != null && transactions != _transactionsVersion) ||
          (_debtsVersion != null && debts != _debtsVersion);

      _productsVersion = products;
      _transactionsVersion = transactions;
      _debtsVersion = debts;

      if (productsChanged) _notify(_productListeners);
      if (transactionsChanged) _notify(_transactionListeners);
    } catch (e) {
      debugPrint('[RealtimeService] status check error: $e');
    } finally {
      _isChecking = false;
    }
  }

  void _notify(Set<VoidCallback> listeners) {
    for (final listener in List.of(listeners)) {
      try {
        listener();
      } catch (e) {
        debugPrint('[RealtimeService] listener error: $e');
      }
    }
  }
}

