import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/product_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/transaction_provider.dart';
import 'screens/admin_navigation_screen.dart';
import 'screens/get_started_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/pin_login_screen.dart';
import 'data/legacy_offline_migration.dart';
import 'services/api_service.dart';
import 'services/realtime_service.dart';
import 'services/update_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.instance.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TindaKo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: context.watch<SettingsProvider>().themeMode,
      home: const AuthenticationWrapper(),
    );
  }
}

class AuthenticationWrapper extends StatefulWidget {
  const AuthenticationWrapper({super.key});

  @override
  State<AuthenticationWrapper> createState() => _AuthenticationWrapperState();
}

class _AuthenticationWrapperState extends State<AuthenticationWrapper> {
  int? _lastSyncedUserId;
  Timer? _idleTimer;

  // Lock after 60 minutes (1 hour) of inactivity
  static const int idleTimeoutSeconds = 3600;

  @override
  void initState() {
    super.initState();
    _startIdleTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        UpdateService.instance.checkForUpdatesOnStartup(context);
      }
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: idleTimeoutSeconds), () {
      final auth = context.read<AuthProvider>();
      if (auth.isLoggedIn && !auth.isLocked && auth.currentUser?.hasPin == true) {
        auth.lock();
      }
    });
  }

  void _handleUserInteraction([_]) {
    _startIdleTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();

    if (auth.isLoggedIn && auth.currentUser != null) {
      final userId = auth.currentUser!.id;
      if (userId != null && _lastSyncedUserId != userId) {
        _lastSyncedUserId = userId;
        if (!auth.isAdmin) {
          RealtimeService.instance.start();
          unawaited(LegacyOfflineMigration.run(userId).then((uploaded) {
            if (uploaded && mounted) {
              context.read<ProductProvider>().fetchProducts(silent: true);
              context.read<TransactionProvider>().fetchTransactions(silent: true);
            }
          }));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            context.read<ProductProvider>().setUserId(userId);
            context.read<CartProvider>().setUserId(userId);
            context.read<TransactionProvider>().setUserId(userId);
            context.read<SettingsProvider>().setUserId(userId);
          });
        } else {
          RealtimeService.instance.stop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            context.read<SettingsProvider>().setUserId(userId);
          });
        }
      }
    } else if (_lastSyncedUserId != null) {
      _lastSyncedUserId = null;
      RealtimeService.instance.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ProductProvider>().clearData();
        context.read<CartProvider>().clear();
        context.read<TransactionProvider>().clearData();
        context.read<SettingsProvider>().setUserId(null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isInitializing) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceDark,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accentOrange.withValues(alpha: 0.15),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.store_rounded,
                    size: 44,
                    color: AppTheme.accentOrange,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'TindaKo',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your Smart Store Partner',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondaryDark,
                ),
              ),
              const SizedBox(height: 36),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentOrange),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Wrap the active application with an idle detector
    return Listener(
      onPointerDown: _handleUserInteraction,
      onPointerMove: _handleUserInteraction,
      onPointerUp: _handleUserInteraction,
      behavior: HitTestBehavior.translucent,
      child: _buildCurrentScreen(auth),
    );
  }

  Widget _buildCurrentScreen(AuthProvider auth) {
    if (!auth.isLoggedIn) {
      if (auth.hasRegisteredUsers && auth.isDeviceConfigured) {
        if (auth.preferPinLogin) {
          return const PinLoginScreen();
        } else {
          return const LoginScreen();
        }
      } else if (auth.hasRegisteredUsers && !auth.isDeviceConfigured) {
        return const LoginScreen();
      } else {
        return const GetStartedScreen();
      }
    }

    if (auth.isLocked) {
      if (!auth.preferPinLogin) {
        return const LoginScreen();
      }
      return const PinLoginScreen(isLockMode: true);
    }

    if (auth.isAdmin) {
      return const AdminNavigationScreen();
    }

    return const MainNavigationScreen();
  }
}
