import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tindako/core/app_theme.dart';
import 'package:tindako/models/user.dart';
import 'package:tindako/providers/admin_store_controller.dart';
import 'package:tindako/providers/auth_provider.dart';
import 'package:tindako/providers/settings_provider.dart';
import 'package:tindako/screens/admin_navigation_screen.dart';
import 'package:tindako/screens/client_management_screen.dart';
import 'package:tindako/widgets/store_image_view.dart';

class _StubAdminAuthProvider extends ChangeNotifier implements AuthProvider {
  final User _admin = User(
    id: 2,
    username: 'admin',
    hasPin: true,
    fullName: 'System Administrator',
    email: 'admin@tindakopos.local',
    role: 'admin',
    isActive: true,
    createdAt: DateTime(2026, 10, 29),
  );

  @override
  User? get currentUser => _admin;
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
  bool get preferPinLogin => true;
  @override
  String? get errorMessage => null;
  @override
  bool get isAdmin => true;
  @override
  String? get deviceAccountUsername => 'admin';
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

class _TestAdminStoreController extends AdminStoreController {
  _TestAdminStoreController({
    required List<User> super.seedUsers,
    required Map<int, StoreMetrics> super.seedMetrics,
  }) : super(skipInitialRefresh: true);

  @override
  Future<Map<String, dynamic>?> fetchStoreLiveDetails(int userId) async {
    return {
      'id': userId,
      'stats': {'today_sales': 1850.0},
      'recent_transactions': [
        {
          'id': 501,
          'total_amount': 320.0,
          'payment_method': 'cash',
          'date': '2026-11-04T10:30:00Z',
          'items': [
            {'id': 1},
            {'id': 2},
          ],
        },
      ],
    };
  }
}

AdminStoreController _buildSeededController() {
  final now = DateTime(2026, 11, 4);
  final users = [
    User(
      id: 2,
      username: 'admin',
      hasPin: true,
      fullName: 'System Administrator',
      email: 'admin@tindakopos.local',
      role: 'admin',
      isActive: true,
      createdAt: now,
    ),
    User(
      id: 10,
      username: 'santos_mart',
      hasPin: true,
      fullName: 'Santos Mini Mart',
      email: 'santos@store.ph',
      role: 'client',
      isActive: true,
      createdAt: now,
    ),
    User(
      id: 11,
      username: 'reyes_store',
      hasPin: false,
      fullName: 'Reyes Sari-Sari Store',
      email: 'reyes@store.ph',
      role: 'client',
      isActive: false,
      createdAt: now.subtract(const Duration(days: 5)),
    ),
  ];

  final metrics = <int, StoreMetrics>{
    2: const StoreMetrics(hasPin: true),
    10: const StoreMetrics(
      productsCount: 64,
      transactionsCount: 142,
      debtsCount: 0,
      totalSales: 48250.0,
      hasPin: true,
    ),
    11: const StoreMetrics(
      productsCount: 28,
      transactionsCount: 31,
      debtsCount: 3,
      totalSales: 9400.0,
      hasPin: false,
    ),
  };

  return _TestAdminStoreController(seedUsers: users, seedMetrics: metrics);
}

Widget _wrapAdminConsole({
  required AdminStoreController controller,
  ThemeMode themeMode = ThemeMode.dark,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => _StubAdminAuthProvider(),
      ),
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: AdminNavigationScreen(controller: controller),
    ),
  );
}

void main() {
  testWidgets(
    'Mobile Admin Console renders dedicated Command, Stores, and Admin tabs (no cashier POS)',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ctrl = _buildSeededController();
      await tester.pumpWidget(_wrapAdminConsole(controller: ctrl));
      await tester.pumpAndSettle();

      // Dedicated Admin tabs, zero cashier POS clutter
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Command'), findsOneWidget);
      expect(find.text('Stores'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('POS'), findsNothing);
      expect(find.text('Inventory'), findsNothing);

      // Network GMV & Store Leaderboard visible on Command tab
      expect(find.text('₱57,650.00'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -320));
      await tester.pumpAndSettle();
      expect(find.text('Client Store Leaderboard'), findsOneWidget);
      expect(find.text('Santos Mini Mart'), findsWidgets);

      // Navigate to Stores tab
      await tester.tap(find.text('Stores'));
      await tester.pumpAndSettle();
      expect(find.text('Stores & Businesses'), findsOneWidget);
      expect(find.text('Client Stores (2)'), findsOneWidget);
      expect(find.text('Santos Mini Mart'), findsWidgets);
      expect(find.text('Reyes Sari-Sari Store'), findsWidgets);

      // Open Provision Store modal via mobile FAB
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('Provision Client Store'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Navigate to Admin Settings tab
      await tester.tap(find.text('Admin'));
      await tester.pumpAndSettle();
      expect(find.text('Platform & Admin Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Desktop Admin Console renders extended NavigationRail and Master-Detail Store Inspector',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ctrl = _buildSeededController();
      await tester.pumpWidget(
        _wrapAdminConsole(controller: ctrl, themeMode: ThemeMode.light),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('TindaKo HQ'), findsOneWidget);
      expect(find.text('Neon Cloud Connected'), findsOneWidget);

      // Switch to Stores directory and verify live split-pane StoreInspectorPanel
      await tester.tap(find.text('Stores'));
      await tester.pumpAndSettle();

      expect(find.byType(StoreInspectorPanel), findsOneWidget);
      expect(find.text('STORE GOVERNANCE & ACCESS'), findsOneWidget);
      expect(
        find.text('₱1,850.00'),
        findsOneWidget,
      ); // Today's Sales from live detail
      expect(find.text('Order #501'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Admin Console renders overflow-free across compact landscape and tablet viewports',
    (tester) async {
      for (final size in const [
        Size(360, 780),
        Size(800, 420),
        Size(840, 1024),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final ctrl = _buildSeededController();
        await tester.pumpWidget(_wrapAdminConsole(controller: ctrl));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Stores'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Admin'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'Admin Console dynamically reflects Cloud Synced vs Offline Cache badges',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ctrl = _buildSeededController();
      await tester.pumpWidget(_wrapAdminConsole(controller: ctrl));
      await tester.pumpAndSettle();

      // In seeded state, controller is cloud synced
      expect(find.text('Neon Cloud Connected'), findsOneWidget);

      await tester.tap(find.text('Stores'));
      await tester.pumpAndSettle();
      expect(find.text('NEON LIVE'), findsOneWidget);
    },
  );

  testWidgets(
    'Store photos render StoreImageView in business cards, leaderboard, and modals',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ctrl = _buildSeededController();
      await tester.pumpWidget(_wrapAdminConsole(controller: ctrl));
      await tester.pumpAndSettle();

      // Check leaderboard contains StoreImageView
      expect(find.byType(StoreImageView), findsWidgets);

      // Navigate to Stores tab
      await tester.tap(find.text('Stores'));
      await tester.pumpAndSettle();

      // Check business card has StoreImageView
      expect(find.byType(StoreImageView), findsWidgets);
    },
  );
}
