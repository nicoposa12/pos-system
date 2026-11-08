import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static final ApiService instance = ApiService._init();
  static const _secureStorageKey = 'api_auth_token_secure';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// Live reachability of the cloud API, derived from real request outcomes
  /// (no extra pings). `false` only after a network-level failure.
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  /// Invoked when an authenticated request is rejected with 401 (token revoked
  /// or expired) so the session can be closed.
  VoidCallback? onUnauthorized;

  late Dio _dio;
  String _baseUrl = '';
  String? _token;

  ApiService._init() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 45),
        headers: {
          'Accept': 'application/json',
        },
      ),
    );

    // Request & Auth Token Interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (_token != null && _token!.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          isOnline.value = true;
          return handler.next(response);
        },
        onError: (DioException e, handler) {
          debugPrint('API Error [${e.response?.statusCode}]: ${e.message}');
          isOnline.value = !isConnectionError(e);
          if (e.response?.statusCode == 401 &&
              e.requestOptions.headers['Authorization'] != null &&
              _isSessionEndpoint(e.requestOptions.path)) {
            onUnauthorized?.call();
          }
          return handler.next(e);
        },
      ),
    );
  }

  /// 401s from credential checks (login, PIN, password) mean "wrong secret",
  /// not "session expired".
  static bool _isSessionEndpoint(String path) {
    return !path.contains('/auth/') || path.endsWith('/auth/me');
  }

  /// True when the request never reached the server (offline, DNS, timeout).
  static bool isConnectionError(Object error) {
    if (error is DioException) {
      return error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          (error.type == DioExceptionType.unknown && error.response == null);
    }
    return false;
  }

  /// Human-readable message for an API failure (validation errors, server
  /// message, or connectivity problems).
  static String describeError(Object error, [String fallback = 'Something went wrong. Please try again.']) {
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'Server took too long to respond. The cloud service may be waking up or busy. Please try again in a moment.';
      }
      if (error.type == DioExceptionType.connectionError ||
          (error.type == DioExceptionType.unknown && error.response == null)) {
        final host = instance._baseUrl.isEmpty ? 'server' : instance._baseUrl;
        return 'Unable to reach $host. Please check your network or Server Settings.';
      }
      final data = error.response?.data;
      if (data is Map) {
        final errors = data['errors'];
        if (errors is Map) {
          for (final entry in errors.values) {
            if (entry is List && entry.isNotEmpty) return entry.first.toString();
          }
        }
        final message = data['message']?.toString();
        if (message != null && message.trim().isNotEmpty) return message;
      }
      if (error.response?.statusCode != null) {
        final code = error.response!.statusCode;
        if (code == 401) return 'Invalid credentials or session expired.';
        if (code == 403) return 'You do not have permission to perform this action.';
        if (code == 404) return 'The requested resource was not found on the server.';
        if (code != null && code >= 500) return 'Server error ($code). Please try again shortly.';
      }
    }
    return fallback;
  }

  String get baseUrl => _baseUrl;
  String? get token => _token;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  /// Initialize stored base URL and auth token
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // Default production cloud API URL
    const String defaultUrl = 'https://pos-system-1-y58u.onrender.com/api';

    final savedUrl = prefs.getString('api_base_url');
    if (savedUrl == null || savedUrl.contains('pos-system-wdlx.onrender.com')) {
      _baseUrl = defaultUrl;
      await prefs.setString('api_base_url', _baseUrl);
    } else {
      _baseUrl = savedUrl;
    }

    // 1. Try reading token from hardware-backed secure storage
    try {
      _token = await _secureStorage.read(key: _secureStorageKey);
    } catch (e) {
      debugPrint('[ApiService] Secure storage read error: $e');
    }

    // 2. Migration fallback: migrate legacy unencrypted SharedPreferences token if present
    if (_token == null || _token!.isEmpty) {
      final legacyToken = prefs.getString('api_auth_token');
      if (legacyToken != null && legacyToken.isNotEmpty) {
        _token = legacyToken;
        try {
          await _secureStorage.write(
            key: _secureStorageKey,
            value: legacyToken,
          );
          await prefs.remove('api_auth_token');
          debugPrint(
            '[ApiService] Transparently upgraded auth token to secure Keystore/Keychain.',
          );
        } catch (_) {}
      }
    }

    _dio.options.baseUrl = _baseUrl;
  }

  /// Update and persist server base URL (e.g. Render URL)
  Future<void> setBaseUrl(String url) async {
    String cleanUrl = url.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    if (!cleanUrl.endsWith('/api')) {
      cleanUrl = '$cleanUrl/api';
    }
    _baseUrl = cleanUrl;
    _dio.options.baseUrl = _baseUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', _baseUrl);
  }

  /// Store or clear auth token securely
  Future<void> setToken(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('api_auth_token'); // Always purge legacy unencrypted key

    try {
      if (token != null && token.isNotEmpty) {
        await _secureStorage.write(key: _secureStorageKey, value: token);
      } else {
        await _secureStorage.delete(key: _secureStorageKey);
      }
    } catch (e) {
      debugPrint('[ApiService] Secure storage write error: $e');
      if (token != null) {
        await prefs.setString('api_auth_token', token);
      }
    }
  }

  /// Quick health check to see if server is online & reachable
  Future<bool> checkConnection([
    String? customUrl,
    Duration timeout = const Duration(seconds: 12),
  ]) async {
    try {
      String target = customUrl?.trim() ?? _baseUrl;
      if (target.endsWith('/')) {
        target = target.substring(0, target.length - 1);
      }
      final pingUrl = target.endsWith('/api')
          ? '$target/auth/ping'
          : (target.endsWith('/auth/ping') ? target : '$target/api/auth/ping');

      final response = await _dio.get(
        pingUrl,
        options: Options(
          validateStatus: (status) => true,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );
      // Even a 404 or auth challenge on ping means the server host responded!
      return response.statusCode != null && response.statusCode! < 500;
    } catch (_) {
      return false;
    }
  }

  // ==========================================
  // AUTH
  // ==========================================

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final response = await _dio.post(
      '/auth/login',
      data: {'username': username, 'password': password},
    );
    final data = response.data as Map<String, dynamic>;
    if (data['token'] != null) {
      await setToken(data['token']);
    }
    return data;
  }

  Future<Map<String, dynamic>> pinLogin({
    required String pin,
    String? username,
  }) async {
    final data = <String, dynamic>{'pin': pin};
    if (username != null && username.isNotEmpty) data['username'] = username;

    final response = await _dio.post('/auth/pin-login', data: data);
    final resData = response.data as Map<String, dynamic>;
    if (resData['token'] != null) {
      await setToken(resData['token']);
    }
    return resData;
  }

  Future<void> updatePin(String newPin) async {
    await _dio.post('/auth/pin', data: {'pin': newPin});
  }

  /// Verifies the signed-in user's PIN on the server without issuing a new token.
  Future<void> verifyPin(String pin) async {
    await _dio.post('/auth/verify-pin', data: {'pin': pin});
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _dio.post(
      '/auth/password',
      data: {'current_password': currentPassword, 'password': newPassword},
    );
  }

  /// Fetches current authenticated user profile including cloud image_path
  Future<Map<String, dynamic>> getCurrentUser() async {
    final response = await _dio.get('/auth/me');
    return response.data as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } catch (_) {}
    await setToken(null);
  }

  // ==========================================
  // PRODUCTS
  // ==========================================

  Future<List<dynamic>> getProducts({String? search, String? category}) async {
    final queryParams = <String, dynamic>{};
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
    if (category != null && category != 'All') {
      queryParams['category'] = category;
    }

    final response = await _dio.get('/products', queryParameters: queryParams);
    return (response.data['products'] as List? ?? []);
  }

  Future<Map<String, dynamic>> createProduct({
    required String name,
    required double price,
    required int stock,
    String? category,
    String? barcode,
    String? variants,
    String? imageFilePath,
  }) async {
    final hasImage = imageFilePath != null &&
        imageFilePath.trim().isNotEmpty &&
        File(imageFilePath).existsSync();

    if (hasImage) {
      final map = <String, dynamic>{
        'name': name,
        'price': price,
        'stock': stock,
        'image': await MultipartFile.fromFile(imageFilePath),
      };
      if (category != null && category.trim().isNotEmpty) {
        map['category'] = category.trim();
      }
      if (barcode != null && barcode.trim().isNotEmpty) {
        map['barcode'] = barcode.trim();
      }
      if (variants != null && variants.trim().isNotEmpty) {
        map['variants'] = variants.trim();
      }

      final formData = FormData.fromMap(map);
      final response = await _dio.post(
        '/products',
        data: formData,
        options: Options(
          headers: {'Accept': 'application/json'},
          contentType: 'multipart/form-data',
        ),
      );
      return response.data as Map<String, dynamic>;
    } else {
      final body = <String, dynamic>{
        'name': name,
        'price': price,
        'stock': stock,
      };
      if (category != null && category.trim().isNotEmpty) {
        body['category'] = category.trim();
      }
      if (barcode != null && barcode.trim().isNotEmpty) {
        body['barcode'] = barcode.trim();
      }
      if (variants != null && variants.trim().isNotEmpty) {
        body['variants'] = variants.trim();
      }

      final response = await _dio.post(
        '/products',
        data: body,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );
      return response.data as Map<String, dynamic>;
    }
  }

  Future<Map<String, dynamic>> updateProduct(
    int id, {
    String? name,
    double? price,
    int? stock,
    String? category,
    String? barcode,
    String? variants,
    String? imageFilePath,
  }) async {
    final hasImage = imageFilePath != null &&
        imageFilePath.trim().isNotEmpty &&
        File(imageFilePath).existsSync();

    if (hasImage) {
      final map = <String, dynamic>{
        '_method': 'PUT',
      };
      if (name != null) map['name'] = name;
      if (price != null) map['price'] = price;
      if (stock != null) map['stock'] = stock;
      if (category != null && category.trim().isNotEmpty) {
        map['category'] = category.trim();
      }
      if (barcode != null && barcode.trim().isNotEmpty) {
        map['barcode'] = barcode.trim();
      }
      if (variants != null && variants.trim().isNotEmpty) {
        map['variants'] = variants.trim();
      }
      map['image'] = await MultipartFile.fromFile(imageFilePath);

      final formData = FormData.fromMap(map);
      final response = await _dio.post(
        '/products/$id',
        data: formData,
        options: Options(
          headers: {'Accept': 'application/json'},
          contentType: 'multipart/form-data',
        ),
      );
      return response.data as Map<String, dynamic>;
    } else {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (price != null) body['price'] = price;
      if (stock != null) body['stock'] = stock;
      if (category != null && category.trim().isNotEmpty) {
        body['category'] = category.trim();
      }
      if (barcode != null && barcode.trim().isNotEmpty) {
        body['barcode'] = barcode.trim();
      }
      if (variants != null && variants.trim().isNotEmpty) {
        body['variants'] = variants.trim();
      }

      final response = await _dio.put(
        '/products/$id',
        data: body,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );
      return response.data as Map<String, dynamic>;
    }
  }

  Future<void> deleteProduct(int id) async {
    await _dio.delete('/products/$id');
  }

  // ==========================================
  // TRANSACTIONS
  // ==========================================

  Future<Map<String, dynamic>> createTransaction(
    Map<String, dynamic> txData,
  ) async {
    final response = await _dio.post('/transactions', data: txData);
    return response.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getTransactions({
    bool all = true,
    int perPage = 100,
    String? since,
  }) async {
    final queryParams = <String, dynamic>{
      'all': all ? 1 : 0,
      'per_page': perPage,
    };
    if (since != null && since.isNotEmpty) {
      queryParams['since'] = since;
    }

    final response = await _dio.get(
      '/transactions',
      queryParameters: queryParams,
    );
    if (response.data is Map && response.data['data'] != null) {
      return response.data['data'] as List;
    }
    return (response.data as List? ?? []);
  }

  Future<void> markTransactionPaid(
    int transactionId, {
    required String paymentMethod,
    double? cashReceived,
    double? changeAmount,
  }) async {
    await _dio.post(
      '/transactions/$transactionId/mark-paid',
      data: {
        'payment_method': paymentMethod,
        'cash_received': cashReceived,
        'change_amount': changeAmount,
      },
    );
  }

  Future<Map<String, dynamic>> getTransaction(int id) async {
    final response = await _dio.get('/transactions/$id');
    return Map<String, dynamic>.from(response.data['transaction'] as Map);
  }

  // ==========================================
  // RETURNS
  // ==========================================

  Future<List<dynamic>> getReturns() async {
    final response = await _dio.get('/returns');
    return (response.data['returns'] as List? ?? []);
  }

  /// Records a return and restores stock server-side. Returns the API payload
  /// including the product's updated `product_stock`.
  Future<Map<String, dynamic>> createReturn(
    int transactionId, {
    required int productId,
    required int quantity,
    String? reason,
  }) async {
    final response = await _dio.post(
      '/transactions/$transactionId/returns',
      data: {
        'product_id': productId,
        'quantity': quantity,
        'reason': reason,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  // ==========================================
  // DEBTS
  // ==========================================

  Future<List<dynamic>> getDebts({String? status}) async {
    final queryParams = <String, dynamic>{};
    if (status != null && status.isNotEmpty) queryParams['status'] = status;

    final response = await _dio.get('/debts', queryParameters: queryParams);
    return (response.data['debts'] as List? ?? []);
  }

  Future<void> payDebt(int id, double amount) async {
    await _dio.post('/debts/$id/pay', data: {'amount': amount});
  }

  // ==========================================
  // REALTIME STATUS & LEGACY OFFLINE DATA UPLOAD
  // ==========================================

  Future<Map<String, dynamic>?> getSyncStatus() async {
    try {
      final response = await _dio.get('/sync/status');
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>> syncOfflineTransactions(
    List<Map<String, dynamic>> transactions,
  ) async {
    if (transactions.isEmpty) return [];
    final response = await _dio.post(
      '/sync',
      data: {'transactions': transactions},
    );
    return (response.data['synced'] as List? ?? []);
  }

  Future<List<dynamic>> syncOfflineProducts(
    List<Map<String, dynamic>> products,
  ) async {
    if (products.isEmpty) return [];
    final response = await _dio.post(
      '/sync/products',
      data: {'products': products},
    );
    return (response.data['synced'] as List? ?? []);
  }

  // ==========================================
  // ADMIN CLIENT MANAGEMENT
  // ==========================================

  Future<Map<String, dynamic>> getAdminClients({
    String? search,
    String? role,
    bool? status,
  }) async {
    final queryParams = <String, dynamic>{};
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (role != null && role.isNotEmpty) queryParams['role'] = role;
    if (status != null) queryParams['status'] = status ? 'true' : 'false';

    final response = await _dio.get(
      '/admin/clients',
      queryParameters: queryParams,
    );
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    throw Exception('Invalid server response format');
  }

  Future<Map<String, dynamic>> createAdminClient({
    required String username,
    required String fullName,
    required String password,
    String? email,
    String? pin,
    String role = 'client',
    bool isActive = true,
    String? imageFilePath,
  }) async {
    final map = <String, dynamic>{
      'username': username,
      'full_name': fullName,
      'password': password,
      'role': role,
      'is_active': isActive ? 1 : 0,
    };
    if (email != null && email.isNotEmpty) map['email'] = email;
    if (pin != null && pin.isNotEmpty) map['pin'] = pin;
    if (imageFilePath != null && File(imageFilePath).existsSync()) {
      map['image'] = await MultipartFile.fromFile(imageFilePath);
    }

    final formData = FormData.fromMap(map);
    final response = await _dio.post(
      '/admin/clients',
      data: formData,
    );
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    throw Exception('Invalid server response format');
  }

  Future<Map<String, dynamic>> getAdminClientDetails(int id) async {
    final response = await _dio.get('/admin/clients/$id');
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    throw Exception('Invalid server response format');
  }

  Future<Map<String, dynamic>> updateAdminClient(
    int id, {
    String? fullName,
    String? email,
    String? role,
    bool? isActive,
    String? imageFilePath,
    bool removeImage = false,
  }) async {
    final map = <String, dynamic>{};
    if (fullName != null) map['full_name'] = fullName;
    if (email != null) map['email'] = email;
    if (role != null) map['role'] = role;
    if (isActive != null) map['is_active'] = isActive ? 1 : 0;
    if (removeImage) {
      map['remove_image'] = 1;
    } else if (imageFilePath != null && File(imageFilePath).existsSync()) {
      map['image'] = await MultipartFile.fromFile(imageFilePath);
    }

    final formData = FormData.fromMap(map);
    final response = await _dio.post(
      '/admin/clients/$id?_method=PUT',
      data: formData,
    );
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    throw Exception('Invalid server response format');
  }

  Future<Map<String, dynamic>> toggleClientStatus(int id) async {
    final response = await _dio.patch('/admin/clients/$id/toggle-status');
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    throw Exception('Invalid server response format');
  }

  Future<Map<String, dynamic>> resetClientCredentials(
    int id, {
    String? password,
    String? pin,
  }) async {
    final data = <String, dynamic>{};
    if (password != null && password.isNotEmpty) data['password'] = password;
    if (pin != null) data['pin'] = pin;

    final response = await _dio.post(
      '/admin/clients/$id/reset-credentials',
      data: data,
    );
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    throw Exception('Invalid server response format');
  }

  Future<Map<String, dynamic>> deleteAdminClient(int id) async {
    final response = await _dio.delete('/admin/clients/$id');
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    throw Exception('Invalid server response format');
  }
}
