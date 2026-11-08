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
import 'package:tindako/screens/get_started_screen.dart';
import 'package:tindako/screens/login_screen.dart';
import 'package:tindako/screens/main_navigation_screen.dart';
import 'package:tindako/screens/pin_login_screen.dart';
import 'package:tindako/screens/settings_screen.dart';
import 'package:tindako/widgets/receipt_dialog.dart';

class _TestAuthProvider extends ChangeNotifier implements AuthProvider {
  final User? _user;
  bool _loggedIn;
  bool _locked;
  final bool _hasUsers;
  bool _preferPin;

  _TestAuthProvider({
    User? user,
    bool loggedIn = true,
    bool locked = false,
    bool hasUsers = true,
    bool preferPin = false,
  }) : _user = user,
       _loggedIn = loggedIn,
       _locked = locked,
       _hasUsers = hasUsers,
       _preferPin = preferPin;

  @override
  User? get currentUser => _user;
  @override
  bool get isLoggedIn => _loggedIn;
  @override
  bool get isLoading => false;
  @override
  bool get isInitializing => false;
  @override
  bool get isLocked => _locked;
  @override
  bool get hasRegisteredUsers => _hasUsers;
  @override
  bool get preferPinLogin => _preferPin;
  @override
  String? get errorMessage => null;
  @override
  bool get isAdmin => _user?.isAdmin ?? false;
  @override
  String? get deviceAccountUsername => _user?.username ?? 'testuser';
  @override
  bool get isDeviceConfigured => true;
  @override
  int get failedPinAttempts => 0;
  @override
  bool get isPinLockedOut => false;
  @override
  int get pinLockoutSecondsRemaining => 0;
  @override
  bool get isLastPinErrorConnection => false;

  @override
  void setPreferPinLogin(bool value) {
    _preferPin = value;
    notifyListeners();
  }

  @override
  void lock() {
    _locked = true;
    notifyListeners();
  }

  @override
  Future<void> reloadCurrentUser() async {}
  @override
  Future<String?> updateProfile({
    String? fullName,
    String? email,
    String? imageFilePath,
    bool removeImage = false,
  }) async => null;

  bool loginSuccessResult = true;

  @override
  Future<bool> login(String username, String password) async =>
      loginSuccessResult;
  @override
  Future<bool> loginWithPin(String pin) async => pin == '1234';
  @override
  Future<bool> verifyPin(String pin) async => pin == '1234';
  @override
  Future<bool> updatePin(String newPin) async => true;
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
  Future<void> logout() async {
    _loggedIn = false;
    notifyListeners();
  }

  @override
  Future<bool> changePassword(
    String currentPassword,
    String newPassword,
  ) async => true;
}

class _TestProductProvider extends ProductProvider {
  final List<Product> _seed;
  _TestProductProvider(this._seed);

  @override
  List<Product> get allProducts => List.unmodifiable(_seed);

  @override
  List<Product> get products => List.unmodifiable(_seed);

  @override
  List<Product> get lowStockProducts =>
      _seed.where((p) => p.stock <= 5).toList();

  @override
  List<String> get categories => const ['All', 'Beverages', 'Canned Goods'];

  @override
  Future<void> fetchProducts({bool silent = false}) async {}
}

class _TestTransactionProvider extends TransactionProvider {
  final List<SaleTransaction> _seed;
  _TestTransactionProvider(this._seed);

  @override
  List<SaleTransaction> get transactions => _seed;

  @override
  double get dailyTotal => 245.0;

  @override
  double get weeklyTotal => 1450.0;

  @override
  double get monthlyTotal => 5820.0;

  @override
  double get yearlyTotal => 28400.0;

  @override
  int get dailyTransactionCount => _seed.length;

  @override
  List<Map<String, dynamic>> get topProducts => const [
    {'name': 'Coca-Cola 1.5L', 'total_qty': 14},
    {'name': 'Mega Sardines', 'total_qty': 9},
  ];

  @override
  List<Map<String, dynamic>> get categorySales => const [
    {'category': 'Beverages', 'total_sales': 980.0},
    {'category': 'Canned Goods', 'total_sales': 470.0},
  ];

  @override
  Map<String, double> getWeeklySalesData() {
    final now = DateTime.now();
    return {
      for (int i = 6; i >= 0; i--)
        DateTime(
              now.year,
              now.month,
              now.day,
            ).subtract(Duration(days: i)).toIso8601String().split('T')[0]:
            (i + 1) * 120.0,
    };
  }

  @override
  Future<void> fetchTransactions({bool silent = false}) async {}
}

Widget _buildTestHarness({
  required Widget child,
  ThemeMode themeMode = ThemeMode.light,
  AuthProvider? authProvider,
}) {
  final now = DateTime.now();
  final testUser = User(
    id: 1,
    username: 'owner',
    hasPin: true,
    fullName: 'Maria Santos',
    createdAt: now,
  );
  final sampleProducts = [
    Product(
      id: 1,
      userId: 1,
      name: 'Coca-Cola 1.5L',
      category: 'Beverages',
      price: 75.0,
      stock: 18,
      barcode: '4801981123456',
      createdAt: now,
    ),
    Product(
      id: 2,
      userId: 1,
      name: 'Mega Sardines Green',
      category: 'Canned Goods',
      price: 25.0,
      stock: 3,
      barcode: '4806502720012',
      createdAt: now,
    ),
  ];
  final sampleTransactions = [
    SaleTransaction(
      id: 101,
      userId: 1,
      totalAmount: 170.0,
      discount: 5.0,
      cashReceived: 200.0,
      change: 30.0,
      paymentMethod: 'cash',
      date: now,
    ),
  ];

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider ?? _TestAuthProvider(user: testUser),
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
      themeMode: themeMode,
      home: child,
    ),
  );
}

void main() {
  testWidgets(
    'Mobile shell renders bottom NavigationBar and navigates across all tabs without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _buildTestHarness(child: const MainNavigationScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('Open POS'), findsOneWidget);

      // Switch to POS tab and add an item to verify floating checkout bar
      await tester.tap(find.text('POS'));
      await tester.pumpAndSettle();
      expect(find.text('Coca-Cola 1.5L'), findsOneWidget);

      await tester.tap(find.text('Coca-Cola 1.5L'));
      await tester.pumpAndSettle();
      expect(find.text('Checkout'), findsOneWidget);

      // Switch to Inventory tab
      await tester.tap(find.text('Inventory'));
      await tester.pumpAndSettle();
      expect(find.text('Low Stock'), findsWidgets);

      // Switch to History tab
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('Order #101'), findsOneWidget);
    },
  );

  testWidgets(
    'Wide tablet/desktop shell renders NavigationRail and split-pane POS cart',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _buildTestHarness(
          child: const MainNavigationScreen(),
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      // Navigate to POS via Dashboard CTA and verify persistent right-hand cart panel
      await tester.tap(find.text('Open POS'));
      await tester.pumpAndSettle();
      expect(find.text('Current Order'), findsOneWidget);
    },
  );

  testWidgets(
    'Auth, onboarding, settings, and product form screens render overflow-free on compact landscape',
    (tester) async {
      tester.view.physicalSize = const Size(800, 420);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final screen in const <Widget>[
        GetStartedScreen(),
        LoginScreen(),
        PinLoginScreen(isLockMode: true),
        SettingsScreen(),
        AddEditProductScreen(),
      ]) {
        await tester.pumpWidget(_buildTestHarness(child: screen));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('ReceiptDialog displays accounting breakdown in clean order', (
    tester,
  ) async {
    final tx = SaleTransaction(
      id: 42,
      userId: 1,
      totalAmount: 145.0,
      discount: 5.0,
      cashReceived: 200.0,
      change: 55.0,
      paymentMethod: 'cash',
      date: DateTime(2026, 10, 29, 14, 30),
    );

    await tester.pumpWidget(
      _buildTestHarness(
        child: Scaffold(
          body: ReceiptDialog(
            transaction: tx,
            items: const [
              {
                'product_name': 'Coca-Cola 1.5L',
                'quantity': 2,
                'subtotal': 150.0,
              },
            ],
            storeName: 'TindaKo Sari-Sari',
            storeAddress: '123 Rizal St.',
            storePhone: '0917 123 4567',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TINDAKO SARI-SARI'), findsOneWidget);
    expect(find.text('Sub-total'), findsOneWidget);
    expect(find.text('Discount'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets(
    'PinLoginScreen toggles preferPinLogin when tapping Use Password Login',
    (tester) async {
      final auth = _TestAuthProvider(
        loggedIn: false,
        hasUsers: true,
        preferPin: true,
      );

      await tester.pumpWidget(
        _buildTestHarness(
          child: const PinLoginScreen(isLockMode: false),
          authProvider: auth,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Use Password Login'), findsOneWidget);
      expect(auth.preferPinLogin, isTrue);

      await tester.tap(find.text('Use Password Login'));
      await tester.pumpAndSettle();

      expect(auth.preferPinLogin, isFalse);
    },
  );

  testWidgets(
    'PinLoginScreen in lock mode displays registered lock UI and sign out option',
    (tester) async {
      final now = DateTime.now();
      final testUser = User(
        id: 1,
        username: 'admin',
        hasPin: true,
        fullName: 'Super Admin',
        createdAt: now,
      );
      final auth = _TestAuthProvider(
        user: testUser,
        loggedIn: true,
        locked: true,
        preferPin: true,
      );

      await tester.pumpWidget(
        _buildTestHarness(
          child: const PinLoginScreen(isLockMode: true),
          authProvider: auth,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('REGISTER LOCKED'), findsOneWidget);
      expect(find.text('Super Admin'), findsOneWidget);
      expect(find.text('Use Password Login'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);

      await tester.tap(find.text('Use Password Login'));
      await tester.pumpAndSettle();
      expect(auth.preferPinLogin, isFalse);
    },
  );

  testWidgets(
    'LoginScreen retains entered username and password without clearing on failed login',
    (tester) async {
      final auth = _TestAuthProvider(
        loggedIn: false,
        hasUsers: true,
        preferPin: false,
      )..loginSuccessResult = false;

      await tester.pumpWidget(
        _buildTestHarness(child: const LoginScreen(), authProvider: auth),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'my_store_user');
      await tester.enterText(find.byType(TextFormField).last, 'my_secret_pass');
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      // Entered credentials must remain intact in the fields
      expect(find.text('my_store_user'), findsOneWidget);
      expect(find.text('my_secret_pass'), findsOneWidget);
      // Full-screen splash loading is NOT shown
      expect(find.text('Your Smart Store Partner'), findsNothing);
    },
  );
}
