import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tindako/models/transaction.dart';
import 'package:tindako/models/user.dart';
import 'package:tindako/providers/auth_provider.dart';
import 'package:tindako/providers/settings_provider.dart';
import 'package:tindako/providers/transaction_provider.dart';
import 'package:tindako/screens/transaction_history_screen.dart';

class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  User? get currentUser => User(id: 1, username: 'test', fullName: 'Tester', createdAt: DateTime.now());
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
  String? get deviceAccountUsername => 'test';
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
  Future<String?> updateProfile({String? fullName, String? email, String? imageFilePath, bool removeImage = false}) async => null;
  @override
  Future<bool> login(String username, String password) async => true;
  @override
  Future<bool> loginWithPin(String pin) async => true;
  @override
  Future<bool> verifyPin(String pin) async => true;
  @override
  Future<bool> updatePin(String newPin) async => true;
  @override
  Future<bool> register(String username, String password, String fullName, {String? pin, String? email, String role = 'client'}) async => true;
  @override
  Future<void> logout() async {}
  @override
  Future<bool> changePassword(String currentPassword, String newPassword) async => true;
}

class _FakeTransactionProvider extends TransactionProvider {
  @override
  List<SaleTransaction> get transactions => [];
  @override
  Future<void> fetchTransactions({bool silent = false}) async {}
}

void main() {
  testWidgets('Open Month and Year Picker dialogs, select values, and verify layout without grey box', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuthProvider()),
          ChangeNotifierProvider<TransactionProvider>(create: (_) => _FakeTransactionProvider()),
          ChangeNotifierProvider<SettingsProvider>(create: (_) => SettingsProvider()),
        ],
        child: const MaterialApp(
          home: TransactionHistoryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Monthly chip
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();

    // Check if dialog is open and month buttons are rendered
    expect(find.text('Select Month & Year'), findsOneWidget);
    expect(find.text('Jan'), findsOneWidget);
    expect(find.text('Dec'), findsOneWidget);

    // Tap Oct and Apply
    await tester.tap(find.text('Oct'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    // Dialog should be dismissed
    expect(find.text('Select Month & Year'), findsNothing);

    // Tap Yearly chip
    await tester.tap(find.text('Yearly'));
    await tester.pumpAndSettle();

    // Check if dialog is open and year buttons are rendered
    expect(find.text('Select Year'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);

    // Tap 2024 and Apply
    await tester.tap(find.text('2024'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    // Dialog should be dismissed and chip updated
    expect(find.text('Select Year'), findsNothing);
  });
}
