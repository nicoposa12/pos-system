import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tindako/core/app_theme.dart';
import 'package:tindako/models/product.dart';
import 'package:tindako/models/user.dart';
import 'package:tindako/providers/auth_provider.dart';
import 'package:tindako/providers/cart_provider.dart';
import 'package:tindako/providers/product_provider.dart';
import 'package:tindako/providers/settings_provider.dart';
import 'package:tindako/providers/transaction_provider.dart';
import 'package:tindako/screens/pos_screen.dart';

class _StubAuthProvider extends ChangeNotifier implements AuthProvider {
  final User _user = User(
    id: 1,
    username: 'cashier',
    password: 'pw',
    fullName: 'Test Cashier',
    createdAt: DateTime(2026, 10, 29),
  );

  @override
  User? get currentUser => _user;
  @override
  bool get isLoggedIn => true;
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
  bool get isAdmin => false;
  @override
  String? get deviceAccountUsername => _user.username;
  @override
  bool get isDeviceConfigured => true;

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
  @override
  Future<bool> changePassword(
    String currentPassword,
    String newPassword,
  ) async => true;
}

class _StubProductProvider extends ProductProvider {
  final List<Product> _items;
  _StubProductProvider(this._items);

  @override
  List<Product> get allProducts => List.unmodifiable(_items);

  @override
  List<Product> get products => List.unmodifiable(_items);

  @override
  List<String> get categories => const ['All', 'Canned', 'Drinks', 'Snacks'];

  @override
  Future<void> fetchProducts() async {}
}

class _StubTransactionProvider extends TransactionProvider {
  @override
  Future<void> fetchTransactions() async {}
}

Widget _wrapPosScreen(List<Product> products) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => _StubAuthProvider()),
      ChangeNotifierProvider<ProductProvider>(
        create: (_) => _StubProductProvider(products),
      ),
      ChangeNotifierProvider<CartProvider>(
        create: (_) => CartProvider()..setUserId(1),
      ),
      ChangeNotifierProvider<TransactionProvider>(
        create: (_) => _StubTransactionProvider(),
      ),
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const PosScreen(),
    ),
  );
}

void main() {
  final now = DateTime(2026, 10, 29);
  final sampleProducts = [
    Product(
      id: 1,
      userId: 1,
      name: 'Coke',
      category: 'Drinks',
      price: 20.0,
      stock: 51,
      createdAt: now,
    ),
    Product(
      id: 2,
      userId: 1,
      name: 'Mega Sardines',
      category: 'Canned',
      price: 25.0,
      stock: 40,
      createdAt: now,
    ),
    Product(
      id: 3,
      userId: 1,
      name: 'Super Crunch',
      category: 'Snacks',
      price: 15.0,
      stock: 32,
      createdAt: now,
    ),
    Product(
      id: 4,
      userId: 1,
      name: 'Sold Out Item',
      category: 'Snacks',
      price: 10.0,
      stock: 0,
      createdAt: now,
    ),
  ];

  testWidgets(
    'POS renders products row-by-row matching Inventory layout across mobile, tablet, and desktop',
    (tester) async {
      for (final size in const [
        Size(360, 800),
        Size(412, 915),
        Size(840, 1024),
        Size(1280, 800),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_wrapPosScreen(sampleProducts));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(GridView), findsNothing);

        // Verify Inventory-style row metadata
        expect(find.text('Coke'), findsOneWidget);
        expect(find.text('Mega Sardines'), findsOneWidget);
        expect(find.text('Super Crunch'), findsOneWidget);
        expect(find.text('51 in stock'), findsOneWidget);
        expect(find.text('40 in stock'), findsOneWidget);
        expect(find.text('Out of stock'), findsOneWidget);

        // Verify vertical row-by-row stacking (same left X, strictly increasing Y)
        final cokePos = tester.getTopLeft(find.text('Coke'));
        final sardinesPos = tester.getTopLeft(find.text('Mega Sardines'));
        final crunchPos = tester.getTopLeft(find.text('Super Crunch'));

        expect(cokePos.dx, closeTo(sardinesPos.dx, 0.5));
        expect(sardinesPos.dx, closeTo(crunchPos.dx, 0.5));
        expect(cokePos.dy, lessThan(sardinesPos.dy));
        expect(sardinesPos.dy, lessThan(crunchPos.dy));
      }
    },
  );

  testWidgets('Tapping a POS product row adds to order and updates badge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrapPosScreen(sampleProducts));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coke'));
    await tester.pumpAndSettle();

    expect(find.text('Checkout'), findsOneWidget);
    expect(find.text('₱20.00'), findsWidgets);
  });
}

