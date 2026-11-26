import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tindako/core/app_theme.dart';
import 'package:tindako/models/product.dart';
import 'package:tindako/models/transaction.dart';
import 'package:tindako/models/user.dart';
import 'package:tindako/providers/auth_provider.dart';
import 'package:tindako/providers/product_provider.dart';
import 'package:tindako/providers/settings_provider.dart';
import 'package:tindako/providers/transaction_provider.dart';
import 'package:tindako/screens/add_edit_product_screen.dart';
import 'package:tindako/screens/best_sellers_screen.dart';
import 'package:tindako/screens/dashboard_screen.dart';
import 'package:tindako/screens/transaction_history_screen.dart';
import 'package:tindako/services/pdf_service.dart';

class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  User? get currentUser => User(
    id: 1,
    username: 'profitstore',
    fullName: 'Profit Store',
    createdAt: DateTime.now(),
  );
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
  String? get deviceAccountUsername => 'profitstore';
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
  void setPreferPinLogin(bool value) {}
  @override
  void lock() {}
  @override
  Future<void> reloadCurrentUser() async {}
  @override
  Future<String?> updateProfile({
    String? fullName,
    String? email,
    String? imageFilePath,
    bool removeImage = false,
  }) async => null;
  @override
  Future<bool> login(String username, String password) async => true;
  @override
  Future<bool> loginWithPin(String pin) async => true;
  @override
  Future<bool> verifyPin(String pin) async => true;
  @override
  Future<bool> updatePin(String newPin) async => true;
  @override
  Future<bool> changePassword(
    String currentPassword,
    String newPassword,
  ) async => true;
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

class _FakeProductProvider extends ProductProvider {
  final List<Product> _seed;
  _FakeProductProvider(this._seed);

  @override
  List<Product> get allProducts => List.unmodifiable(_seed);
  @override
  List<Product> get products => List.unmodifiable(_seed);
  @override
  List<Product> get lowStockProducts =>
      _seed.where((p) => p.stock <= 5).toList();
  @override
  Future<void> fetchProducts({bool silent = false}) async {}
}

class _FakeTransactionProvider extends TransactionProvider {
  final List<SaleTransaction> _seed;
  _FakeTransactionProvider(this._seed);

  @override
  List<SaleTransaction> get transactions => List.unmodifiable(_seed);
  @override
  Future<void> fetchTransactions({bool silent = false}) async {}
}

Widget _wrapWithProviders(
  Widget child, {
  List<Product> products = const [],
  List<SaleTransaction> transactions = const [],
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuthProvider()),
      ChangeNotifierProvider<ProductProvider>(
        create: (_) => _FakeProductProvider(products),
      ),
      ChangeNotifierProvider<TransactionProvider>(
        create: (_) => _FakeTransactionProvider(transactions),
      ),
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: child,
    ),
  );
}

void main() {
  group('Product & Variant profit calculations', () {
    test('parses cost_price and computes unitProfit, margin, and stock values', () {
      final product = Product.fromJson({
        'id': 1,
        'user_id': 1,
        'name': 'Bottled Water',
        'price': 25.0,
        'cost_price': 15.0,
        'stock': 40.0,
        'unit': 'bottle',
        'variants': [
          {'name': '500ml', 'price': 25.0, 'cost_price': 15.0, 'stock': 20},
          {'name': '1L', 'price': 40.0, 'costPrice': 26.0, 'stock': 20},
        ],
      });

      expect(product.hasCostPrice, isTrue);
      expect(product.costPrice, 15.0);
      expect(product.unitProfit, 10.0);
      expect(product.profitMarginPercent, closeTo(40.0, 0.01));
      expect(product.stockCostValue, 600.0);
      expect(product.stockRetailValue, 1000.0);
      expect(product.potentialStockProfit, 400.0);

      expect(product.variants[0].costPrice, 15.0);
      expect(product.variants[0].unitProfit, 10.0);
      expect(product.variants[1].costPrice, 26.0);
      expect(product.variants[1].unitProfit, 14.0);
    });

    test('returns null profit metrics when cost_price is not set', () {
      final product = Product.fromJson({
        'id': 2,
        'user_id': 1,
        'name': 'Legacy Item',
        'price': 50.0,
        'stock': 10.0,
      });

      expect(product.hasCostPrice, isFalse);
      expect(product.unitProfit, isNull);
      expect(product.profitMarginPercent, isNull);
      expect(product.stockCostValue, isNull);
    });
  });

  group('SaleTransaction profit calculations', () {
    test('computes profit with discount and partial/full returns accurately', () {
      final txWithDiscount = SaleTransaction.fromJson({
        'id': 10,
        'order_number': 1,
        'user_id': 1,
        'total_amount': 180.0,
        'discount': 20.0,
        'payment_method': 'cash',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'items': [
          {
            'product_id': 1,
            'quantity': 2,
            'subtotal': 200.0,
            'unit_cost': 60.0,
            'product': {'id': 1, 'name': 'Rice 2kg', 'category': 'Grains'},
          },
        ],
        'returns': [],
      });

      expect(txWithDiscount.hasCostData, isTrue);
      expect(txWithDiscount.hasCompleteCostData, isTrue);
      expect(txWithDiscount.totalCost, 120.0);
      expect(txWithDiscount.totalProfit, 60.0); // 200 - 120 - 20

      // Partial return of 1 unit out of 2 (with 0 discount)
      final txPartialReturn = SaleTransaction.fromJson({
        'id': 11,
        'order_number': 2,
        'user_id': 1,
        'total_amount': 100.0,
        'discount': 0.0,
        'payment_method': 'cash',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'items': [
          {
            'product_id': 1,
            'quantity': 2,
            'subtotal': 200.0,
            'unit_cost': 60.0,
            'product': {'id': 1, 'name': 'Rice 2kg'},
          },
        ],
        'returns': [
          {'product_id': 1, 'quantity': 1},
        ],
      });

      expect(txPartialReturn.totalAmount, 100.0);
      expect(txPartialReturn.totalCost, 60.0);
      expect(txPartialReturn.totalProfit, 40.0);

      // Full return produces 0 profit
      final txFullReturn = SaleTransaction.fromJson({
        'id': 12,
        'order_number': 3,
        'user_id': 1,
        'total_amount': 0.0,
        'discount': 10.0,
        'payment_method': 'cash',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'items': [
          {
            'product_id': 1,
            'quantity': 2,
            'subtotal': 200.0,
            'unit_cost': 60.0,
            'product': {'id': 1, 'name': 'Rice 2kg'},
          },
        ],
        'returns': [
          {'product_id': 1, 'quantity': 2},
        ],
      });

      expect(txFullReturn.totalCost, 0.0);
      expect(txFullReturn.totalProfit, 0.0);
    });

    test('legacy uncosted transactions return null profit instead of inflating margin', () {
      final legacyTx = SaleTransaction.fromJson({
        'id': 20,
        'user_id': 1,
        'total_amount': 150.0,
        'discount': 0.0,
        'payment_method': 'cash',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'items': [
          {
            'product_id': 5,
            'quantity': 3,
            'subtotal': 150.0,
            'unit_cost': null,
            'product': {'id': 5, 'name': 'Old Item'},
          },
        ],
        'returns': [],
      });

      expect(legacyTx.hasCostData, isFalse);
      expect(legacyTx.totalCost, isNull);
      expect(legacyTx.totalProfit, isNull);
    });

    test('mixed order applies proportional discount only to costed items', () {
      final mixedTx = SaleTransaction.fromJson({
        'id': 21,
        'user_id': 1,
        'total_amount': 180.0,
        'discount': 20.0,
        'payment_method': 'cash',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'items': [
          {
            'product_id': 1,
            'quantity': 1,
            'subtotal': 100.0,
            'unit_cost': 60.0,
            'product': {'id': 1, 'name': 'Costed Item'},
          },
          {
            'product_id': 2,
            'quantity': 1,
            'subtotal': 100.0,
            'unit_cost': null,
            'product': {'id': 2, 'name': 'Uncosted Item'},
          },
        ],
        'returns': [],
      });

      expect(mixedTx.hasCostData, isTrue);
      expect(mixedTx.hasCompleteCostData, isFalse);
      expect(mixedTx.totalCost, 60.0);
      // Costed item accounts for 50% of subtotal -> 50% of ₱20 discount = ₱10 -> 100 - 60 - 10 = 30
      expect(mixedTx.totalProfit, 30.0);
    });
  });

  group('UI profit previews & responsive rendering', () {
    testWidgets('AddEditProductScreen shows live unit profit and loss warnings', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithProviders(const AddEditProductScreen()),
      );
      await tester.pumpAndSettle();

      final costField = find.widgetWithText(TextFormField, 'Cost Price (₱)');
      final sellField = find.widgetWithText(TextFormField, 'Selling Price (₱)');

      await tester.enterText(costField, '45');
      await tester.enterText(sellField, '65');
      await tester.pump();

      expect(find.textContaining('Profit: +₱20.00 / pcs'), findsOneWidget);
      expect(find.textContaining('Margin: 30.8%'), findsOneWidget);

      // Selling below cost triggers loss warning
      await tester.enterText(sellField, '40');
      await tester.pump();

      expect(find.textContaining('Loss: -₱5.00 / pcs'), findsOneWidget);
    });

    testWidgets('Dashboard & BestSellers show profit cleanly without overflow on 320x568', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.now();
      final products = [
        Product(
          id: 1,
          userId: 1,
          name: 'Coke Mismo',
          category: 'Beverages',
          price: 25.0,
          costPrice: 17.0,
          stock: 30,
          unit: 'pcs',
          createdAt: now,
        ),
        Product(
          id: 2,
          userId: 1,
          name: 'Premium Coffee',
          category: 'Beverages',
          price: 120.0,
          costPrice: 70.0,
          stock: 15,
          unit: 'pack',
          createdAt: now,
        ),
      ];
      final transactions = [
        SaleTransaction.fromJson({
          'id': 1,
          'order_number': 1,
          'user_id': 1,
          'total_amount': 245.0,
          'discount': 0.0,
          'payment_method': 'cash',
          'created_at': now.toUtc().toIso8601String(),
          'items': [
            {
              'product_id': 1,
              'quantity': 5,
              'subtotal': 125.0,
              'unit_cost': 17.0,
              'product': {'id': 1, 'name': 'Coke Mismo', 'category': 'Beverages'},
            },
            {
              'product_id': 2,
              'quantity': 1,
              'subtotal': 120.0,
              'unit_cost': 70.0,
              'product': {'id': 2, 'name': 'Premium Coffee', 'category': 'Beverages'},
            },
          ],
          'returns': [],
        }),
      ];

      await tester.pumpWidget(
        _wrapWithProviders(
          const DashboardScreen(),
          products: products,
          transactions: transactions,
        ),
      );
      await tester.pumpAndSettle();

      // Today's profit = (125 - 85) + (120 - 70) = 90.00
      expect(find.text('Profit: ₱90.00'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _wrapWithProviders(
          const BestSellersScreen(),
          products: products,
          transactions: transactions,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Top Profit'), findsOneWidget);
      expect(find.textContaining('+₱90.00'), findsOneWidget);

      // Scroll the sort chips and list into view on compact 320x568 viewport
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -280));
      await tester.pumpAndSettle();

      // Tap Top Profit chip: Premium Coffee (+₱50) should rank above Coke (+₱40)
      await tester.tap(find.text('Top Profit'));
      await tester.pumpAndSettle();

      final coffeeY = tester.getTopLeft(find.text('Premium Coffee')).dy;
      final cokeY = tester.getTopLeft(find.text('Coke Mismo')).dy;
      expect(coffeeY, lessThan(cokeY));
      expect(find.text('15 pack left'), findsOneWidget);
      expect(find.text('30 pcs left'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'TransactionHistoryScreen shows period profit, order card profit, and order detail profit without overflow on 320x568',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final now = DateTime.now();
        final transactions = [
          SaleTransaction.fromJson({
            'id': 1,
            'order_number': 137,
            'user_id': 1,
            'total_amount': 245.0,
            'discount': 0.0,
            'cash_received': 250.0,
            'change_amount': 5.0,
            'payment_method': 'cash',
            'created_at': now.toUtc().toIso8601String(),
            'items': [
              {
                'product_id': 1,
                'quantity': 5,
                'subtotal': 125.0,
                'unit_cost': 17.0,
                'product': {'id': 1, 'name': 'Coke Mismo', 'category': 'Beverages'},
              },
              {
                'product_id': 2,
                'quantity': 1,
                'subtotal': 120.0,
                'unit_cost': 70.0,
                'product': {'id': 2, 'name': 'Premium Coffee', 'category': 'Beverages'},
              },
            ],
            'returns': [],
          }),
        ];

        await tester.pumpWidget(
          _wrapWithProviders(
            const TransactionHistoryScreen(
              initialFilter: TransactionFilter.daily,
            ),
            transactions: transactions,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Est. Profit'), findsOneWidget);
        expect(find.textContaining('+₱90.00 (36.7%)'), findsOneWidget);
        expect(find.text('+₱90.00 profit'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Tap order card to inspect Order Profit breakdown
        await tester.tap(find.text('Order #137'));
        await tester.pumpAndSettle();

        expect(find.text('ORDER PROFIT (INTERNAL)'), findsOneWidget);
        expect(find.text('Original Cost (COGS)'), findsOneWidget);
        expect(find.text('₱155.00'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Sales report PDF bytes with profit data
        final pdfBytes = await PdfService.buildSalesReportPdfBytes(
          transactions: transactions,
          periodLabel: 'Today',
          storeName: 'Jicca Store',
          storeAddress: 'Manila, PH',
        );
        expect(pdfBytes.length, greaterThan(1000));
        expect(String.fromCharCodes(pdfBytes.take(5)), '%PDF-');
      },
    );
  });
}
