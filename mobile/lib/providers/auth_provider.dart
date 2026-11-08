import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  static const _snapshotKey = 'user_session_snapshot_v2';
  static const _deviceUsernameKey = 'device_account_username';

  User? _currentUser;
  bool _isLoggedIn = false;
  bool _isLoading = false;
  bool _isInitializing = true;
  bool _isLocked = false;
  bool _hasRegisteredUsers = false;
  bool _preferPinLogin = true;
  String? _errorMessage;
  String? _deviceAccountUsername;
  int _failedPinAttempts = 0;
  DateTime? _pinLockoutUntil;
  bool _isLastPinErrorConnection = false;

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  bool get isLocked => _isLocked;
  bool get hasRegisteredUsers => _hasRegisteredUsers;
  bool get preferPinLogin => _preferPinLogin;
  String? get errorMessage => _errorMessage;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  String? get deviceAccountUsername => _deviceAccountUsername;
  bool get isDeviceConfigured =>
      _deviceAccountUsername != null && _deviceAccountUsername!.isNotEmpty;
  int get failedPinAttempts => _failedPinAttempts;
  bool get isPinLockedOut =>
      _pinLockoutUntil != null && DateTime.now().isBefore(_pinLockoutUntil!);
  int get pinLockoutSecondsRemaining => isPinLockedOut
      ? _pinLockoutUntil!.difference(DateTime.now()).inSeconds + 1
      : 0;
  bool get isLastPinErrorConnection => _isLastPinErrorConnection;

  void setPreferPinLogin(bool value) {
    _preferPinLogin = value;
    notifyListeners();
  }

  AuthProvider() {
    ApiService.instance.onUnauthorized = _onSessionExpired;
    _checkLoginStatus();
  }

  void _onSessionExpired() {
    debugPrint('[AuthProvider] Active session was revoked or expired on server.');
    logout();
  }

  void lock() {
    if (_isLoggedIn) {
      _isLocked = true;
      _preferPinLogin = true;
      notifyListeners();
    }
  }

  Future<void> _checkLoginStatus() async {
    _isLoading = true;
    _isInitializing = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _deviceAccountUsername = prefs.getString(_deviceUsernameKey);
      if (_deviceAccountUsername == 'developer') {
        await prefs.remove(_deviceUsernameKey);
        _deviceAccountUsername = null;
      }

      final rawSnapshot = prefs.getString(_snapshotKey);
      if (rawSnapshot != null && rawSnapshot.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawSnapshot);
          if (decoded is Map<String, dynamic>) {
            _currentUser = User.fromJson(decoded);
            _isLoggedIn = true;
            if (_currentUser!.hasPin) {
              _isLocked = true;
              _preferPinLogin = true;
            }
          }
        } catch (_) {}
      }

      _hasRegisteredUsers =
          isDeviceConfigured || _currentUser != null || prefs.containsKey('logged_in_username');

      // Re-validate against authoritative server if token is present
      if (ApiService.instance.isAuthenticated) {
        reloadCurrentUser();
      }
    } catch (e) {
      debugPrint('[AuthProvider] checkLoginStatus error: $e');
    } finally {
      _isLoading = false;
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> _saveSession(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snapshotKey, jsonEncode(user.toJson()));
    await prefs.setString('logged_in_username', user.username);
    if (!user.isAdmin) {
      await prefs.setString(_deviceUsernameKey, user.username);
      _deviceAccountUsername = user.username;
    }
  }

  Future<bool> login(String username, String password) async {
    if (username.trim().toLowerCase() == 'developer') {
      _errorMessage = 'The developer account has been removed. Please log in as admin.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.instance.login(
        username: username.trim(),
        password: password,
      );

      final rawUser = res['user'];
      if (rawUser is Map) {
        final user = User.fromJson(Map<String, dynamic>.from(rawUser));
        if (!user.isActive) {
          _errorMessage =
              'This account has been deactivated. Please contact an administrator.';
          _isLoading = false;
          notifyListeners();
          return false;
        }

        _currentUser = user;
        _isLoggedIn = true;
        _isLocked = false;
        _hasRegisteredUsers = true;
        await _saveSession(user);

        _isLoading = false;
        notifyListeners();
        return true;
      }
      throw Exception('Unexpected server response format');
    } catch (e) {
      _errorMessage = ApiService.describeError(e, 'Invalid username or password.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginWithPin(String pin) async {
    if (isPinLockedOut) {
      _errorMessage =
          'Too many failed attempts. Device locked for $pinLockoutSecondsRemaining seconds.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    _isLastPinErrorConnection = false;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final scopedUsername = _currentUser?.username ??
        _deviceAccountUsername ??
        prefs.getString(_deviceUsernameKey);

    // 1. If currently in lock-screen mode for an active session
    if (_isLoggedIn && _currentUser != null) {
      try {
        await ApiService.instance.verifyPin(pin);
        _failedPinAttempts = 0;
        _pinLockoutUntil = null;
        _isLocked = false;
        _isLoading = false;
        _isLastPinErrorConnection = false;
        notifyListeners();
        return true;
      } catch (e) {
        if (ApiService.isConnectionError(e)) {
          _isLastPinErrorConnection = true;
          _errorMessage = ApiService.describeError(e);
          _isLoading = false;
          notifyListeners();
          return false;
        }
        _isLastPinErrorConnection = false;
        _recordFailedPinAttempt('Incorrect PIN for this register.');
        return false;
      }
    }

    // 2. PIN login on register start
    try {
      final res = await ApiService.instance.pinLogin(
        pin: pin,
        username: scopedUsername,
      );

      final rawUser = res['user'];
      if (rawUser is Map) {
        final user = User.fromJson(Map<String, dynamic>.from(rawUser));
        if (!user.isActive) {
          _errorMessage =
              'This account has been deactivated. Please contact an administrator.';
          _isLoading = false;
          notifyListeners();
          return false;
        }

        _currentUser = user;
        _isLoggedIn = true;
        _isLocked = false;
        _hasRegisteredUsers = true;
        _failedPinAttempts = 0;
        _pinLockoutUntil = null;
        _isLastPinErrorConnection = false;
        await _saveSession(user);

        _isLoading = false;
        notifyListeners();
        return true;
      }
      throw Exception('Unexpected server response format');
    } catch (e) {
      if (ApiService.isConnectionError(e)) {
        _isLastPinErrorConnection = true;
        _errorMessage = ApiService.describeError(e);
        _isLoading = false;
        notifyListeners();
        return false;
      }
      _isLastPinErrorConnection = false;
      _recordFailedPinAttempt(ApiService.describeError(e, 'Invalid PIN.'));
      return false;
    }
  }

  /// Verifies the current user's PIN on the server (e.g. before deleting a product).
  Future<bool> verifyPin(String pin) async {
    try {
      await ApiService.instance.verifyPin(pin);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _recordFailedPinAttempt([String? customMessage]) {
    _failedPinAttempts++;
    if (_failedPinAttempts >= 5) {
      _pinLockoutUntil = DateTime.now().add(const Duration(seconds: 30));
      _errorMessage = 'Too many failed attempts. Device locked for 30 seconds.';
    } else {
      final remaining = 5 - _failedPinAttempts;
      _errorMessage = '${customMessage ?? "Invalid PIN."} ($remaining attempts remaining)';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> updatePin(String newPin) async {
    if (_currentUser == null) return false;
    try {
      await ApiService.instance.updatePin(newPin);
      _currentUser = _currentUser!.copyWith(hasPin: true);
      await _saveSession(_currentUser!);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = ApiService.describeError(e, 'Failed to update PIN.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> changePassword(String currentPassword, String newPassword) async {
    if (_currentUser == null) return false;
    try {
      await ApiService.instance.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      return true;
    } catch (e) {
      _errorMessage = ApiService.describeError(e, 'Failed to change password.');
      notifyListeners();
      return false;
    }
  }

  Future<void> reloadCurrentUser() async {
    if (!ApiService.instance.isAuthenticated) return;
    try {
      final res = await ApiService.instance.getCurrentUser();
      final rawUser = res['user'];
      if (rawUser is Map) {
        final user = User.fromJson(Map<String, dynamic>.from(rawUser));
        if (!user.isActive) {
          logout();
          return;
        }
        _currentUser = user;
        await _saveSession(user);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[AuthProvider] reloadCurrentUser error: $e');
    }
  }

  Future<bool> register(
    String username,
    String password,
    String fullName, {
    String? pin,
    String? email,
    String role = 'client',
  }) async {
    _errorMessage =
        'Self-registration is disabled. Client accounts must be created by an administrator.';
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    try {
      await ApiService.instance.logout();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_snapshotKey);
    await prefs.remove('logged_in_username');

    _currentUser = null;
    _isLoggedIn = false;
    _isLocked = false;
    _preferPinLogin = true;
    _hasRegisteredUsers = isDeviceConfigured;
    notifyListeners();
  }
}
