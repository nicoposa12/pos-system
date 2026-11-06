import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tindako/core/app_theme.dart';
import 'package:tindako/models/product.dart';
import 'package:tindako/models/transaction.dart';
import 'package:tindako/models/user.dart';
import 'package:tindako/providers/auth_provider.dart';
import 'package:tindako/providers/cart_provider.dart';
import 'package:tindako/providers/product_provider.dart';
import 'package:tindako/providers/settings_provider.dart';
import 'package:tindako/providers/transaction_provider.dart';
import 'package:tindako/screens/add_edit_product_screen.dart';
import 'package:tindako/screens/dashboard_screen.dart';
import 'package:tindako/screens/get_started_screen.dart';
import 'package:tindako/screens/login_screen.dart';
import 'package:tindako/screens/main_navigation_screen.dart';
import 'package:tindako/screens/pin_login_screen.dart';
import 'package:tindako/screens/pos_screen.dart';
import 'package:tindako/screens/product_list_screen.dart';
import 'package:tindako/screens/settings_screen.dart';
import 'package:tindako/screens/transaction_history_screen.dart';

class _TestAuthProvider extends ChangeNotifier implements AuthProvider {
  final User? _user;
  _TestAuthProvider({User? user}) : _user = user;

  @override
  User? get currentUser => _user;
  @override
  bool get isLoggedIn => _user != null;
  @override
  bool get isLoading => false;
  @override
  bool get isInitializing => false;
  @override
  bool get isLocked => false;
  @override
  bool get hasRegisteredUsers => true;
  @override
  bool get preferPinLogin => false;
  @override
  String? get errorMessage => null;
  @override
  bool get isAdmin => _user?.isAdmin ?? false;
  @override
  String? get deviceAccountUsername => _user?.username ?? 'teststore';
  @override
  bool get isDeviceConfigured => true;
  @override
  int get failedPinAttempts => 0;
  @override
  bool get isPinLockedOut => false;
  @override
  int get pinLockoutSecondsRemaining => 0;

  @override
  void setPreferPinLogin(bool value) {}
  @override
  void lock() {}
  @override
  Future<void> reloadCurrentUser() async {}
  @override
  Future<bool> login(String username, String password) async => true;
  @override
  Future<bool> loginWithPin(String pin) async => true;
  @override
  Future<bool> updatePin(String newPin) async => true;
  @override
  Future<bool> changePassword(String currentPassword, String newPassword) async => true;
  @override
  Future<bool> register(
    String username,
    String password,
    String fullName, {
    String? pin,
    String? email,
    String role = 'client',
  }) async => true;
  @override
  Future<void> logout() async {}
}

class _TestProductProvider extends ProductProvider {
  final List<Product> _seed;
  _TestProductProvider(this._seed);

  @override
  List<Product> get allProducts => List.unmodifiable(_seed);
  @override
  List<Product> get products => List.unmodifiable(_seed);
  @override
  List<Product> get lowStockProducts => _seed.where((p) => p.stock <= 5).toList();
  @override
  List<String> get categories => const ['All', 'Beverages', 'Noodles'];
  @override
  Future<void> fetchProducts({bool silent = false}) async {}
}

class _TestTransactionProvider extends TransactionProvider {
  final List<SaleTransaction> _seed;
  _TestTransactionProvider(this._seed);

  @override
  List<SaleTransaction> get transactions => _seed;
  @override
  double get dailyTotal => 14500.0;
  @override
  double get weeklyTotal => 68200.0;
  @override
  double get monthlyTotal => 245000.0;
  @override
  double get yearlyTotal => 1890000.0;
  @override
  int get dailyTransactionCount => 32;
  @override
  List<Map<String, dynamic>> get topProducts => const [
    {'name': 'San Miguel Pale Pilsen', 'total_qty': 24},
    {'name': 'Lucky Me Pancit Canton', 'total_qty': 18},
  ];
  @override
  List<Map<String, dynamic>> get categorySales => const [
    {'category': 'Beverages', 'total_sales': 1560.0},
    {'category': 'Noodles', 'total_sales': 420.0},
  ];
  @override
  Map<String, double> getWeeklySalesData() {
    final now = DateTime.now();
    return {
      for (int i = 6; i >= 0; i--)
        DateTime(now.year, now.month, now.day).subtract(Duration(days: i)).toIso8601String().split('T')[0]:
            (i + 1) * 350.0,
    };
  }
  @override
  Future<void> fetchTransactions({bool silent = false}) async {}
}

Widget _wrap(Widget child, {bool isAdmin = false}) {
  final now = DateTime.now();
  final user = User(
    id: 1,
    username: isAdmin ? 'admin' : 'cashier1',
    password: 'password',
    pin: '1234',
    fullName: isAdmin ? 'Admin User' : 'Cashier One',
    role: isAdmin ? 'admin' : 'client',
    createdAt: now,
  );
  final sampleProducts = [
    Product(
      id: 1,
      userId: 1,
      name: 'San Miguel Pale Pilsen 330ml Can',
      price: 65.0,
      stock: 48,
      category: 'Beverages',
      createdAt: now,
    ),
    Product(
      id: 2,
      userId: 1,
      name: 'Lucky Me Instant Pancit Canton Kalamansi',
      price: 18.0,
      stock: 3,
      category: 'Noodles',
      createdAt: now,
    ),
  ];
  final sampleTransactions = [
    SaleTransaction(
      id: 101,
      userId: 1,
      totalAmount: 148.0,
      discount: 0.0,
      cashReceived: 200.0,
      change: 52.0,
      paymentMethod: 'cash',
      date: now,
    ),
  ];

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(
        value: _TestAuthProvider(user: user),
      ),
      ChangeNotifierProvider<ProductProvider>(
        create: (_) => _TestProductProvider(sampleProducts),
      ),
      ChangeNotifierProvider<CartProvider>(
        create: (_) => CartProvider()..setUserId(1),
      ),
      ChangeNotifierProvider<TransactionProvider>(
        create: (_) => _TestTransactionProvider(sampleTransactions),
      ),
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: child,
    ),
  );
}

void main() {
  const androidScreenSizes = <String, Size>{
    'Compact Budget Android (320x568)': Size(320, 568),
    'Standard Android (360x740)': Size(360, 740),
    'Flagship Android (412x915)': Size(412, 915),
    'Landscape Compact Android (640x360)': Size(640, 360),
    'Foldable / Small Tablet (600x960)': Size(600, 960),
  };

  for (final entry in androidScreenSizes.entries) {
    testWidgets(
      'All primary screens render overflow-free on ${entry.key}',
      (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final screens = <Widget>[
          const GetStartedScreen(),
          const LoginScreen(),
          const PinLoginScreen(isLockMode: true),
          const SettingsScreen(),
          const AddEditProductScreen(),
          DashboardScreen(
            onOpenPos: () {},
            onOpenHistory: (_) {},
            onOpenInventory: (_) {},
          ),
          const PosScreen(),
          ProductListScreen(),
          const TransactionHistoryScreen(),
          const MainNavigationScreen(),
        ];

        for (final screen in screens) {
          FlutterErrorDetails? caughtDetails;
          final prevOnError = FlutterError.onError;
          FlutterError.onError = (details) {
            caughtDetails = details;
            prevOnError?.call(details);
          };

          await tester.pumpWidget(_wrap(screen));
          await tester.pumpAndSettle();

          FlutterError.onError = prevOnError;

          if (caughtDetails != null) {
            debugPrint('=== DETAILED OVERFLOW FOR ${screen.runtimeType} ===');
            debugPrint(caughtDetails!.toString());
          }

          final err = tester.takeException();
          expect(
            err,
            isNull,
            reason: 'Screen ${screen.runtimeType} threw an exception on ${entry.key}',
          );
        }
      },
    );
  }
}
