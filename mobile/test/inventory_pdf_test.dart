import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tindako/core/app_theme.dart';
import 'package:tindako/models/product.dart';
import 'package:tindako/models/user.dart';
import 'package:tindako/providers/auth_provider.dart';
import 'package:tindako/providers/product_provider.dart';
import 'package:tindako/providers/settings_provider.dart';
import 'package:tindako/screens/product_list_screen.dart';
import 'package:tindako/services/pdf_service.dart';

class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  User? get currentUser => User(
    id: 1,
    username: 'invstore',
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
  String? get deviceAccountUsername => 'invstore';
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
  List<String> get categories => const ['All', 'Drinks', 'Canned Goods'];
  @override
  Future<void> fetchProducts({bool silent = false}) async {}
}

void main() {
  final now = DateTime.now();
  final sampleProducts = [
    Product(
      id: 1,
      userId: 1,
      name: 'Coke Mismo',
      category: 'Drinks',
      price: 25.0,
      costPrice: 17.0,
      stock: 30,
      unit: 'pcs',
      createdAt: now,
    ),
    Product(
      id: 2,
      userId: 1,
      name: 'Sardines',
      category: 'Canned Goods',
      price: 28.0,
      costPrice: 21.0,
      stock: 3,
      unit: 'can',
      createdAt: now,
    ),
    Product(
      id: 3,
      userId: 1,
      name: 'Empty Item',
      category: 'Canned Goods',
      price: 40.0,
      costPrice: 30.0,
      stock: 0,
      unit: 'pcs',
      createdAt: now,
    ),
  ];

  test(
    'PdfService builds valid Inventory PDF bytes for All Items, Healthy, Low Stock, and Out of Stock',
    () async {
      final cases = <(String, List<Product>)>[
        ('All Items', sampleProducts),
        ('Healthy', sampleProducts.where((p) => p.stock > 5).toList()),
        (
          'Low Stock',
          sampleProducts.where((p) => p.stock > 0 && p.stock <= 5).toList(),
        ),
        ('Out of Stock', sampleProducts.where((p) => p.stock <= 0).toList()),
      ];

      for (final entry in cases) {
        final bytes = await PdfService.buildInventoryReportPdfBytes(
          products: entry.$2,
          filterLabel: entry.$1,
          sortLabel: 'Name (A-Z)',
          storeName: 'Jicca Store',
          storeAddress: 'Manila, PH',
          storePhone: '0917-123-4567',
        );

        expect(bytes.length, greaterThan(1000));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      }
    },
  );

  testWidgets(
    'Inventory Export PDF sheet switches All Items, Healthy, Low Stock, Out of Stock cleanly on 320x568',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(
              create: (_) => _FakeAuthProvider(),
            ),
            ChangeNotifierProvider<ProductProvider>(
              create: (_) => _FakeProductProvider(sampleProducts),
            ),
            ChangeNotifierProvider<SettingsProvider>(
              create: (_) => SettingsProvider(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ProductListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Export PDF'));
      await tester.pumpAndSettle();

      expect(find.text('Export Inventory PDF'), findsOneWidget);
      expect(find.text('All Items (3)'), findsOneWidget);
      expect(find.text('Healthy (1)'), findsOneWidget);
      expect(find.text('Low Stock (1)'), findsOneWidget);
      expect(find.text('Out of Stock (1)'), findsOneWidget);

      for (final label in const [
        'Healthy (1)',
        'Low Stock (1)',
        'Out of Stock (1)',
        'All Items (3)',
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      expect(find.text('Print / Preview'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
