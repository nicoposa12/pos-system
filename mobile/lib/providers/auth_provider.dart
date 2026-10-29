import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/database_helper.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  User? _currentUser;
  bool _isLoggedIn = false;
  bool _isLoading = false;
  bool _isLocked = false;
  bool _hasRegisteredUsers = false;
  bool _preferPinLogin = true;

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  bool get isLocked => _isLocked;
  bool get hasRegisteredUsers => _hasRegisteredUsers;
  bool get preferPinLogin => _preferPinLogin;

  void setPreferPinLogin(bool value) {
    _preferPinLogin = value;
    notifyListeners();
  }

  AuthProvider() {
    _checkLoginStatus();
  }

  void lock() {
    if (_isLoggedIn) {
      _isLocked = true;
      notifyListeners();
    }
  }

  Future<void> _checkLoginStatus() async {
    _isLoading = true;
    notifyListeners();

    try {
      _hasRegisteredUsers = await DatabaseHelper.instance.hasUsers();
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('logged_in_username');

      if (username != null) {
        _currentUser = await DatabaseHelper.instance.getUser(username);
        if (_currentUser != null) {
          _isLoggedIn = true;
          if (_currentUser!.pin != null) {
            _isLocked = true;
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking login status: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    // 1. Try Online Login First
    try {
      final res = await ApiService.instance.login(username: username, password: password);
      if (res['user'] != null) {
        final userData = res['user'];
        // Cache or sync into SQLite
        var localUser = await DatabaseHelper.instance.getUser(username);
        if (localUser == null) {
          final newUser = User(
            id: userData['id'],
            username: userData['username'],
            password: password,
            fullName: userData['full_name'] ?? username,
            pin: null,
            createdAt: DateTime.now(),
          );
          await DatabaseHelper.instance.createUser(newUser);
          localUser = newUser;
        }

        _currentUser = localUser;
        _isLoggedIn = true;
        _isLocked = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('logged_in_username', username);
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Online login attempt error (falling back to offline): $e');
    }

    // 2. Offline Fallback via SQLite
    final user = await DatabaseHelper.instance.loginUser(username, password);
    if (user != null) {
      _currentUser = user;
      _isLoggedIn = true;
      _isLocked = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('logged_in_username', username);
      _isLoading = false;
      notifyListeners();
      return true;
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> loginWithPin(String pin) async {
    _isLoading = true;
    notifyListeners();

    // If locked locally
    if (_isLoggedIn && _currentUser != null) {
      if (_currentUser!.pin == pin) {
        _isLocked = false;
        _isLoading = false;
        notifyListeners();
        return true;
      }
    }

    // 1. Try Online PIN Login
    try {
      final res = await ApiService.instance.pinLogin(pin: pin);
      if (res['user'] != null) {
        final userData = res['user'];
        var localUser = await DatabaseHelper.instance.getUser(userData['username']);
        if (localUser != null) {
          _currentUser = localUser;
        } else {
          final newUser = User(
            id: userData['id'],
            username: userData['username'],
            password: '',
            fullName: userData['full_name'] ?? userData['username'],
            pin: pin,
            createdAt: DateTime.now(),
          );
          await DatabaseHelper.instance.createUser(newUser);
          _currentUser = newUser;
        }
        _isLoggedIn = true;
        _isLocked = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('logged_in_username', _currentUser!.username);
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Online PIN login error (falling back to offline): $e');
    }

    // 2. Offline PIN Login via SQLite
    final user = await DatabaseHelper.instance.loginWithPin(pin);
    if (user != null) {
      _currentUser = user;
      _isLoggedIn = true;
      _isLocked = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('logged_in_username', user.username);
      _isLoading = false;
      notifyListeners();
      return true;
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> updatePin(String newPin) async {
    if (_currentUser == null) return false;

    // Try online
    try {
      await ApiService.instance.updatePin(newPin);
    } catch (_) {}

    // Update local SQLite
    final db = await DatabaseHelper.instance.database;
    final result = await db.update(
      'users',
      {'pin': newPin},
      where: 'id = ?',
      whereArgs: [_currentUser!.id],
    );

    if (result > 0) {
      _currentUser = _currentUser!.copyWith(pin: newPin);
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> register(String username, String password, String fullName, {String? pin, String? email}) async {
    _isLoading = true;
    notifyListeners();

    int? onlineUserId;

    // 1. Try Online Register First
    try {
      final res = await ApiService.instance.register(
        username: username,
        fullName: fullName,
        password: password,
        pin: pin,
        email: email,
      );
      if (res['user'] != null) {
        onlineUserId = res['user']['id'];
      }
    } catch (e) {
      debugPrint('Online register attempt failed (continuing local cache): $e');
    }

    // 2. Save in local SQLite
    final existingUser = await DatabaseHelper.instance.getUser(username);
    if (existingUser != null) {
      _isLoading = false;
      notifyListeners();
      return false;
    }

    final newUser = User(
      id: onlineUserId,
      username: username,
      password: password,
      fullName: fullName,
      pin: pin,
      createdAt: DateTime.now(),
    );

    final result = await DatabaseHelper.instance.createUser(newUser);

    if (result > 0) {
      _hasRegisteredUsers = true;
      _isLoading = false;
      notifyListeners();
      return true;
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    await ApiService.instance.logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('logged_in_username');
    _currentUser = null;
    _isLoggedIn = false;
    _isLocked = false;
    _preferPinLogin = true;
    _hasRegisteredUsers = await DatabaseHelper.instance.hasUsers();
    notifyListeners();
  }

  Future<bool> changePassword(String currentPassword, String newPassword) async {
    if (_currentUser == null) return false;

    final user = await DatabaseHelper.instance.loginUser(_currentUser!.username, currentPassword);
    if (user == null) return false;

    final result = await DatabaseHelper.instance.updateUserPassword(_currentUser!.id!, newPassword);
    if (result > 0) {
      _currentUser = await DatabaseHelper.instance.getUser(_currentUser!.username);
      notifyListeners();
      return true;
    }
    return false;
  }
}
