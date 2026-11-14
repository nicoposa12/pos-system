import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:tindako/core/app_theme.dart';
import 'package:tindako/models/product.dart';
import 'package:tindako/models/transaction.dart';
import 'package:tindako/models/user.dart';
import 'package:tindako/providers/auth_provider.dart';
import 'package:tindako/providers/product_provider.dart';
import 'package:tindako/providers/settings_provider.dart';
import 'package:tindako/providers/transaction_provider.dart';
import 'package:tindako/screens/best_sellers_screen.dart';
import 'package:tindako/screens/dashboard_screen.dart';
import 'package:tindako/widgets/period_picker_dialogs.dart';

class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  User? get currentUser => User(
    id: 1,
    username: 'store1',
    fullName: 'Jicca Store',
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
  String? get deviceAccountUsername => 'store1';
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

Widget _wrapTest({
  required Widget child,
  required List<Product> products,
  required List<SaleTransaction> transactions,
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
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 10, 0);
  final currentWeekStart = startOfCalendarWeek(today);
  final previousWeekDay = DateTime(
    currentWeekStart.year,
    currentWeekStart.month,
    currentWeekStart.day - 2,
    14,
    0,
  );
  final prevMonth = DateTime(now.year, now.month - 1, 10, 14, 0);
  final prevYear = DateTime(now.year - 1, 5, 12, 11, 0);

  final sampleProducts = [
    Product(
      id: 1,
      userId: 1,
      name: 'Coke',
      category: 'Beverages',
      price: 25,
      stock: 20,
      unit: 'pcs',
      createdAt: now,
    ),
    Product(
      id: 2,
      userId: 1,
      name: 'Super Crunch',
      category: 'Snacks',
      price: 10,
      stock: 30,
      unit: 'pcs',
      createdAt: now,
    ),
    Product(
      id: 3,
      userId: 1,
      name: 'Coffee Pack',
      category: 'Beverages',
      price: 120,
      stock: 15,
      unit: 'pack',
      createdAt: now,
    ),
    Product(
      id: 4,
      userId: 1,
      name: 'Sardines',
      category: 'Canned',
      price: 28,
      stock: 12,
      unit: 'can',
      createdAt: now,
    ),
    Product(
      id: 5,
      userId: 1,
      name: 'Soy Sauce',
      category: 'Condiments',
      price: 45,
      stock: 10,
      unit: 'btl',
      createdAt: now,
    ),
    Product(
      id: 6,
      userId: 1,
      name: 'Old Calendar Item',
      category: 'Archive',
      price: 300,
      stock: 4,
      unit: 'pcs',
      createdAt: now,
    ),
  ];

  final sampleTransactions = [
    SaleTransaction(
      id: 101,
      userId: 1,
      totalAmount: 195,
      date: today,
      items: [
        {
          'product_id': 1,
          'product_name': 'Coke',
          'category': 'Beverages',
          'quantity': 5,
          'subtotal': 125.0,
        },
        {
          'product_id': 2,
          'product_name': 'Super Crunch',
          'category': 'Snacks',
          'quantity': 7,
          'subtotal': 70.0,
        },
        // Fully returned item should be excluded from product sales
        {
          'product_id': 99,
          'product_name': 'Returned Item',
          'category': 'Other',
          'quantity': 0,
          'subtotal': 0.0,
        },
      ],
    ),
    SaleTransaction(
      id: 102,
      userId: 1,
      totalAmount: 653,
      date: previousWeekDay,
      items: [
        {
          'product_id': 3,
          'product_name': 'Coffee Pack',
          'category': 'Beverages',
          'quantity': 4,
          'subtotal': 480.0,
        },
        {
          'product_id': 4,
          'product_name': 'Sardines',
          'category': 'Canned',
          'quantity': 3,
          'subtotal': 84.0,
        },
        {
          'product_id': 5,
          'product_name': 'Soy Sauce',
          'category': 'Condiments',
          'quantity': 2,
          'subtotal': 90.0,
        },
      ],
    ),
    SaleTransaction(
      id: 103,
      userId: 1,
      totalAmount: 100,
      date: prevMonth,
      items: [
        {
          'product_id': 1,
          'product_name': 'Coke',
          'category': 'Beverages',
          'quantity': 4,
          'subtotal': 100.0,
        },
      ],
    ),
    SaleTransaction(
      id: 104,
      userId: 1,
      totalAmount: 600,
      date: prevYear,
      items: [
        {
          'product_id': 6,
          'product_name': 'Old Calendar Item',
          'category': 'Archive',
          'quantity': 2,
          'subtotal': 600.0,
        },
      ],
    ),
  ];

  test('TransactionProvider.getProductSales returns all products, sorts, and excludes returned zero items', () {
    final provider = _FakeTransactionProvider(sampleTransactions);

    final all = provider.getProductSales();
    expect(all.length, 6);
    expect(all.any((e) => e['name'] == 'Returned Item'), isFalse);
    // Coke: 5 (today) + 4 (prevMonth) = 9 sold
    expect(all.first['name'], 'Coke');
    expect(all.first['total_sold'], 9.0);
    expect(all.first['order_count'], 2);

    // Sort by revenue: Old Calendar Item (600) is #1
    final byRev = provider.getProductSales(sortByRevenue: true);
    expect(byRev.first['name'], 'Old Calendar Item');
    expect(byRev.first['total_revenue'], 600.0);

    // Daily filter: only Coke & Super Crunch
    final daily = provider.getProductSales(
      filter: (tx) =>
          tx.date.year == today.year &&
          tx.date.month == today.month &&
          tx.date.day == today.day,
    );
    expect(daily.length, 2);
    expect(daily.map((e) => e['name']), ['Super Crunch', 'Coke']);
  });

  testWidgets('Dashboard Best Sellers tab shows Show All button and opens BestSellersScreen', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrapTest(
        child: const DashboardScreen(),
        products: sampleProducts,
        transactions: sampleTransactions,
      ),
    );
    await tester.pumpAndSettle();

    // Show All is hidden on 7-Day Trend tab
    expect(find.text('Show All'), findsNothing);

    // Switch to Best Sellers tab
    await tester.tap(find.text('Best Sellers'));
    await tester.pumpAndSettle();

    expect(find.text('Show All'), findsOneWidget);

    // Tap Show All -> navigates to BestSellersScreen showing all 6 products
    await tester.tap(find.text('Show All'));
    await tester.pumpAndSettle();

    expect(find.byType(BestSellersScreen), findsOneWidget);
    expect(find.text('Ranked Products (6)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Soy Sauce'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Soy Sauce'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Old Calendar Item'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Old Calendar Item'), findsOneWidget);
  });

  testWidgets('BestSellersScreen filters across Daily, Weekly, Monthly, Yearly and supports search & sort', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrapTest(
        child: const BestSellersScreen(),
        products: sampleProducts,
        transactions: sampleTransactions,
      ),
    );
    await tester.pumpAndSettle();

    // All Time shows all 6 sold products
    expect(find.text('All Time'), findsOneWidget);
    expect(find.text('Ranked Products (6)'), findsOneWidget);
    expect(find.text('Coke'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Old Calendar Item'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Old Calendar Item'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
    await tester.pumpAndSettle();

    // Daily shows today's products only
    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    expect(find.text('Ranked Products (2)'), findsOneWidget);
    expect(find.text('Super Crunch'), findsOneWidget);
    expect(find.text('Coke'), findsOneWidget);
    expect(find.text('Old Calendar Item'), findsNothing);
    expect(find.text('Coffee Pack'), findsNothing);

    // Weekly shows this calendar week by default, and supports stepping + week picker dialog
    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    expect(
      find.text('This Week (${formatWeekRangeLabel(currentWeekStart)})'),
      findsOneWidget,
    );
    expect(find.text('Ranked Products (2)'), findsOneWidget);

    // Step backward (<) to previous week shows Order #102 products
    await tester.tap(find.byTooltip('Previous'));
    await tester.pumpAndSettle();
    final prevWeekStart = startOfCalendarWeek(previousWeekDay);
    expect(
      find.text('Week of ${formatWeekRangeLabel(prevWeekStart)}'),
      findsOneWidget,
    );
    expect(find.text('Ranked Products (3)'), findsOneWidget);
    expect(find.text('Coffee Pack'), findsOneWidget);
    expect(find.text('Old Calendar Item'), findsNothing);

    // Open Select Week dialog via calendar button and pick This Week
    await tester.tap(find.byTooltip('Select Week'));
    await tester.pumpAndSettle();
    expect(find.text('Select Week'), findsOneWidget);
    expect(find.text('This Week'), findsOneWidget);
    await tester.tap(find.text('This Week'));
    await tester.pumpAndSettle();
    expect(
      find.text('This Week (${formatWeekRangeLabel(currentWeekStart)})'),
      findsOneWidget,
    );

    // Monthly -> step backward (<) to previous month shows Coke (prevMonth)
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous'));
    await tester.pumpAndSettle();
    expect(find.text(DateFormat('MMMM yyyy').format(prevMonth)), findsOneWidget);
    expect(find.text('Coke'), findsOneWidget);

    // Yearly -> step backward (<) to previous year shows Old Calendar Item
    await tester.tap(find.text('Yearly'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous'));
    await tester.pumpAndSettle();
    expect(find.text('Year ${prevYear.year}'), findsOneWidget);
    expect(find.text('Old Calendar Item'), findsOneWidget);
    expect(find.text('Coke'), findsNothing);

    // Back to All + Search + Sort
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top Revenue'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Coffee');
    await tester.pumpAndSettle();
    expect(find.text('Coffee Pack'), findsOneWidget);
    expect(find.text('Coke'), findsNothing);

    // Tap product to open breakdown sheet
    await tester.tap(find.text('Coffee Pack'));
    await tester.pumpAndSettle();
    expect(find.text('Order #102'), findsOneWidget);
  });

  testWidgets('BestSellersScreen renders overflow-free on compact 320x568 viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrapTest(
        child: const BestSellersScreen(),
        products: sampleProducts,
        transactions: sampleTransactions,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Best Sellers'), findsOneWidget);
  });

  testWidgets('Select Week dialog allows choosing any calendar week and applying', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrapTest(
        child: const BestSellersScreen(initialPeriod: BestSellersPeriod.weekly),
        products: sampleProducts,
        transactions: sampleTransactions,
      ),
    );
    await tester.pumpAndSettle();

    // Tap active Weekly chip to open Select Week dialog
    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    expect(find.text('Select Week'), findsOneWidget);

    if (previousWeekDay.month != today.month) {
      await tester.tap(find.byTooltip('Previous Month'));
      await tester.pumpAndSettle();
    }

    // Tap day number in previous week row, then Apply
    await tester.tap(find.text('${previousWeekDay.day}').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final prevWeekStart = startOfCalendarWeek(previousWeekDay);
    expect(
      find.text('Week of ${formatWeekRangeLabel(prevWeekStart)}'),
      findsOneWidget,
    );
    expect(find.text('Coffee Pack'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
