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
  String? _errorMessage;
  String? _deviceAccountUsername;

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  bool get isLocked => _isLocked;
  bool get hasRegisteredUsers => _hasRegisteredUsers;
  bool get preferPinLogin => _preferPinLogin;
  String? get errorMessage => _errorMessage;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  String? get deviceAccountUsername => _deviceAccountUsername;
  bool get isDeviceConfigured => _deviceAccountUsername != null && _deviceAccountUsername!.isNotEmpty;

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
      _preferPinLogin = true;
      notifyListeners();
    }
  }

  Future<void> _checkLoginStatus() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Ensure default local admin account exists
      await DatabaseHelper.instance.ensureDefaultAdmin();

      _hasRegisteredUsers = await DatabaseHelper.instance.hasUsers();
      final prefs = await SharedPreferences.getInstance();
      _deviceAccountUsername = prefs.getString('device_account_username');
      if (_deviceAccountUsername == 'developer') {
        await prefs.remove('device_account_username');
        _deviceAccountUsername = null;
      }
      final username = prefs.getString('logged_in_username');

      if (username == 'developer') {
        await prefs.remove('logged_in_username');
        _currentUser = null;
        _isLoggedIn = false;
        _isLocked = false;
      } else if (username != null) {
        _currentUser = await DatabaseHelper.instance.getUser(username);
        if (_currentUser != null) {
          if (!_currentUser!.isActive) {
            // Deactivated user logged out automatically
            await prefs.remove('logged_in_username');
            _currentUser = null;
            _isLoggedIn = false;
          } else {
            _isLoggedIn = true;
            if (_currentUser!.pin != null) {
              _isLocked = true;
              _preferPinLogin = true;
            }
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
    if (username.trim().toLowerCase() == 'developer') {
      _errorMessage = 'The developer account has been removed. Please log in as admin.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // 1. Try Online Login First
    try {
      final res = await ApiService.instance.login(username: username, password: password);
      if (res['user'] != null) {
        final userData = res['user'];

        // Check if deactivated
        if (userData['is_active'] == false) {
          _errorMessage = 'This account has been deactivated. Please contact an administrator.';
          _isLoading = false;
          notifyListeners();
          return false;
        }

        // Cache or sync into SQLite
        var localUser = await DatabaseHelper.instance.getUser(username);
        final defaultRole = (username == 'admin') ? 'admin' : 'client';
        if (localUser == null) {
          final newUser = User(
            id: userData['id'],
            username: userData['username'],
            password: password,
            fullName: userData['full_name'] ?? username,
            email: userData['email'],
            role: userData['role'] ?? defaultRole,
            isActive: userData['is_active'] ?? true,
            pin: null,
            createdAt: DateTime.now(),
          );
          await DatabaseHelper.instance.createUser(newUser);
          localUser = newUser;
        } else {
          // Update cached role & status
          final updated = localUser.copyWith(
            id: userData['id'] ?? localUser.id,
            fullName: userData['full_name'] ?? localUser.fullName,
            email: userData['email'] ?? localUser.email,
            role: userData['role'] ?? (localUser.role == 'client' && defaultRole == 'admin' ? 'admin' : localUser.role),
            isActive: userData['is_active'] ?? localUser.isActive,
          );
          await DatabaseHelper.instance.updateUser(updated);
          localUser = updated;
        }

        _currentUser = localUser;
        _isLoggedIn = true;
        _isLocked = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('logged_in_username', username);
        if (username != 'admin') {
          await prefs.setString('device_account_username', username);
          _deviceAccountUsername = username;
        }
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
      if (!user.isActive) {
        _errorMessage = 'This account has been deactivated. Please contact an administrator.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _currentUser = user;
      _isLoggedIn = true;
      _isLocked = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('logged_in_username', username);
      if (username != 'admin') {
        await prefs.setString('device_account_username', username);
        _deviceAccountUsername = username;
      }
      _isLoading = false;
      notifyListeners();
      return true;
    }

    _errorMessage = 'Invalid username or password.';
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> loginWithPin(String pin) async {
    if (pin == '0000') {
      _errorMessage = 'Invalid PIN.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final scopedUsername = _currentUser?.username ?? _deviceAccountUsername ?? prefs.getString('device_account_username');

    // If locked locally
    if (_isLoggedIn && _currentUser != null) {
      if (_currentUser!.pin == pin) {
        if (!_currentUser!.isActive) {
          _errorMessage = 'This account has been deactivated. Please contact an administrator.';
          _isLoading = false;
          notifyListeners();
          return false;
        }
        _isLocked = false;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      // Master Administrator PIN override for terminal maintenance
      if (pin == '9999') {
        final adminUser = await DatabaseHelper.instance.getUser('admin');
        if (adminUser != null && adminUser.isActive) {
          _currentUser = adminUser;
          _isLoggedIn = true;
          _isLocked = false;
          await prefs.setString('logged_in_username', 'admin');
          _isLoading = false;
          notifyListeners();
          return true;
        }
      }

      _errorMessage = 'Incorrect PIN for this register.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // 1. Try Online PIN Login (strictly scoped to this device's account)
    try {
      final res = await ApiService.instance.pinLogin(pin: pin, username: scopedUsername);
      if (res['user'] != null) {
        final userData = res['user'];

        if (userData['is_active'] == false) {
          _errorMessage = 'This account has been deactivated. Please contact an administrator.';
          _isLoading = false;
          notifyListeners();
          return false;
        }

        final uname = userData['username'] ?? '';
        final defaultPinRole = (uname == 'admin') ? 'admin' : 'client';
        var localUser = await DatabaseHelper.instance.getUser(uname);
        if (localUser != null) {
          final updated = localUser.copyWith(
            role: userData['role'] ?? (localUser.role == 'client' && defaultPinRole == 'admin' ? 'admin' : localUser.role),
            isActive: userData['is_active'] ?? localUser.isActive,
          );
          await DatabaseHelper.instance.updateUser(updated);
          _currentUser = updated;
        } else {
          final newUser = User(
            id: userData['id'],
            username: uname,
            password: '',
            fullName: userData['full_name'] ?? uname,
            email: userData['email'],
            role: userData['role'] ?? defaultPinRole,
            isActive: userData['is_active'] ?? true,
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

    // 2. Offline PIN Login via SQLite (scoped to this device's account)
    final user = await DatabaseHelper.instance.loginWithPin(pin, scopedUsername: scopedUsername);
    if (user != null) {
      if (!user.isActive) {
        _errorMessage = 'This account has been deactivated. Please contact an administrator.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _currentUser = user;
      _isLoggedIn = true;
      _isLocked = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('logged_in_username', user.username);
      _isLoading = false;
      notifyListeners();
      return true;
    }

    _errorMessage = 'Invalid PIN.';
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

  Future<bool> register(
    String username,
    String password,
    String fullName, {
    String? pin,
    String? email,
    String role = 'client',
  }) async {
    _isLoading = true;
    _errorMessage = null;
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
      _errorMessage = 'Username already exists.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    final newUser = User(
      id: onlineUserId,
      username: username,
      password: password,
      fullName: fullName,
      email: email,
      pin: pin,
      role: role,
      isActive: true,
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

  Future<void> reloadCurrentUser() async {
    if (_currentUser != null) {
      final updated = await DatabaseHelper.instance.getUser(_currentUser!.username);
      if (updated != null) {
        _currentUser = updated;
        notifyListeners();
      }
    }
  }

  Future<void> logout() async {
    try {
      await ApiService.instance.logout();
    } catch (_) {}
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
