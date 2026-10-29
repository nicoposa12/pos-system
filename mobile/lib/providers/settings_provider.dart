import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  int? _userId;
  String _storeName = 'Mini-Store';
  String _storeAddress = 'Your Address Here';
  String _storePhone = '09XX XXX XXXX';
  String _gcashNumber = '';
  String _gcashQrPath = '';
  ThemeMode _themeMode = ThemeMode.system;

  String get storeName => _storeName;
  String get storeAddress => _storeAddress;
  String get storePhone => _storePhone;
  String get gcashNumber => _gcashNumber;
  String get gcashQrPath => _gcashQrPath;
  ThemeMode get themeMode => _themeMode;

  void setUserId(int? id) {
    if (_userId != id) {
      _userId = id;
      _loadSettings();
    }
  }

  String _getKey(String base) {
    if (_userId == null) return base;
    return '${base}_$_userId';
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _storeName = prefs.getString(_getKey('storeName')) ?? 'Mini-Store';
    _storeAddress = prefs.getString(_getKey('storeAddress')) ?? 'Your Address Here';
    _storePhone = prefs.getString(_getKey('storePhone')) ?? '09XX XXX XXXX';
    _gcashNumber = prefs.getString(_getKey('gcashNumber')) ?? '';
    _gcashQrPath = prefs.getString(_getKey('gcashQrPath')) ?? '';
    final themeIndex = prefs.getInt(_getKey('themeMode')) ?? 0;
    _themeMode = ThemeMode.values[themeIndex];
    notifyListeners();
  }

  Future<void> updateStoreInfo({
    required String name,
    required String address,
    required String phone,
    String? gcashNumber,
    String? gcashQrPath,
  }) async {
    _storeName = name;
    _storeAddress = address;
    _storePhone = phone;
    if (gcashNumber != null) _gcashNumber = gcashNumber;
    if (gcashQrPath != null) _gcashQrPath = gcashQrPath;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_getKey('storeName'), name);
    await prefs.setString(_getKey('storeAddress'), address);
    await prefs.setString(_getKey('storePhone'), phone);
    await prefs.setString(_getKey('gcashNumber'), _gcashNumber);
    await prefs.setString(_getKey('gcashQrPath'), _gcashQrPath);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_getKey('themeMode'), mode.index);
    notifyListeners();
  }
}
