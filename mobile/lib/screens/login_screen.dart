import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (context.read<AuthProvider>().isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final success = await context.read<AuthProvider>().login(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;
    if (success) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      HapticFeedback.vibrate();
      final errorMsg = context.read<AuthProvider>().errorMessage ?? 'Invalid username or password';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: AppTheme.accentRose,
        ),
      );
    }
  }

  void _openPinLogin() {
    context.read<AuthProvider>().setPreferPinLogin(true);
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canPop = Navigator.canPop(context);

    return Scaffold(
      backgroundColor: AppTheme.surfaceDark,
      body: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: IgnorePointer(
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.accentOrange.withValues(alpha: 0.14),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (canPop) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              color: AppTheme.textPrimaryDark,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: AppTheme.cardDark,
                              side: const BorderSide(
                                color: AppTheme.borderDark,
                              ),
                            ),
                            tooltip: 'Back',
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Brand Header
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: AppTheme.cardDark,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTheme.borderDark),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.asset(
                              'assets/images/app_icon.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.storefront_rounded,
                                color: AppTheme.accentOrange,
                                size: 28,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'WELCOME BACK',
                                  style: TextStyle(
                                    color: AppTheme.accentOrange,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Sign in to TindaKo',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => _showServerSettingsDialog(context),
                            icon: const Icon(
                              Icons.dns_rounded,
                              color: AppTheme.textSecondaryDark,
                              size: 20,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: AppTheme.cardDark,
                              side: const BorderSide(
                                color: AppTheme.borderDark,
                              ),
                            ),
                            tooltip: 'Server Settings',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Enter your credentials to access your POS register and inventory.',
                        style: TextStyle(
                          color: AppTheme.textSecondaryDark,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Sign-In Card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppTheme.cardDark,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.borderDark),
                        ),
                        child: AutofillGroup(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Username',
                                  style: TextStyle(
                                    color: AppTheme.textPrimaryDark,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _usernameController,
                                  autofillHints: const [AutofillHints.username],
                                  textInputAction: TextInputAction.next,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimaryDark,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: _authInputDecoration(
                                    hint: 'Enter your username',
                                    icon: Icons.person_outline_rounded,
                                  ),
                                  validator: (value) =>
                                      value == null || value.trim().isEmpty
                                      ? 'Please enter your username'
                                      : null,
                                ),
                                const SizedBox(height: 18),
                                const Text(
                                  'Password',
                                  style: TextStyle(
                                    color: AppTheme.textPrimaryDark,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  autofillHints: const [AutofillHints.password],
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _handleLogin(),
                                  style: const TextStyle(
                                    color: AppTheme.textPrimaryDark,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: _authInputDecoration(
                                    hint: 'Enter your password',
                                    icon: Icons.lock_outline_rounded,
                                    suffixIcon: IconButton(
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: AppTheme.textSecondaryDark,
                                        size: 20,
                                      ),
                                      tooltip: _obscurePassword
                                          ? 'Show password'
                                          : 'Hide password',
                                    ),
                                  ),
                                  validator: (value) =>
                                      value == null || value.isEmpty
                                      ? 'Please enter your password'
                                      : null,
                                ),
                                const SizedBox(height: 24),

                                // Primary Sign-In Button
                                SizedBox(
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: auth.isLoading
                                        ? null
                                        : _handleLogin,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.accentOrange,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          AppTheme.accentOrange.withValues(
                                            alpha: 0.85,
                                          ),
                                      disabledForegroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: auth.isLoading
                                        ? const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                height: 20,
                                                width: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2.4,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(Colors.white),
                                                ),
                                              ),
                                              SizedBox(width: 12),
                                              Text(
                                                'Signing in...',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                            ],
                                          )
                                        : const Text(
                                            'Sign In',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                  ),
                                ),

                                if (auth.isDeviceConfigured) ...[
                                  const SizedBox(height: 12),

                                  // Quick PIN Login Button
                                  SizedBox(
                                    height: 48,
                                    child: OutlinedButton.icon(
                                      onPressed: auth.isLoading
                                          ? null
                                          : _openPinLogin,
                                      icon: const Icon(
                                        Icons.dialpad_rounded,
                                        size: 18,
                                        color: AppTheme.accentOrange,
                                      ),
                                      label: const Text('Quick PIN Login'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            AppTheme.textPrimaryDark,
                                        side: const BorderSide(
                                          color: AppTheme.borderDark,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Administrator Managed Account Info
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.admin_panel_settings_outlined,
                              size: 16,
                              color: AppTheme.textSecondaryDark,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Client accounts are managed by your administrator.',
                                style: TextStyle(
                                  color: AppTheme.textSecondaryDark.withValues(alpha: 0.8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Server Connection Config Shortcut
                      Center(
                        child: TextButton.icon(
                          onPressed: () => _showServerSettingsDialog(context),
                          icon: const Icon(
                            Icons.cloud_sync_outlined,
                            size: 14,
                            color: AppTheme.textSecondaryDark,
                          ),
                          label: Text(
                            'Server: ${ApiService.instance.baseUrl.replaceAll('/api', '')}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondaryDark,
                              decoration: TextDecoration.underline,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _authInputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: AppTheme.textSecondaryDark,
        fontSize: 14,
      ),
      prefixIcon: Icon(icon, color: AppTheme.textSecondaryDark, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppTheme.surfaceDark,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.borderDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.borderDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.accentOrange, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.accentRose),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.accentRose, width: 1.8),
      ),
    );
  }

  void _showServerSettingsDialog(BuildContext context) {
    final urlController = TextEditingController(text: ApiService.instance.baseUrl);
    bool isTesting = false;
    bool? testSuccess;
    String? testMessage;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppTheme.borderDark),
          ),
          title: const Row(
            children: [
              Icon(Icons.dns_rounded, color: AppTheme.accentOrange, size: 22),
              SizedBox(width: 10),
              Text(
                'Server Endpoint',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Configure the API URL for cloud or local network backend:',
                  style: TextStyle(
                    color: AppTheme.textSecondaryDark,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: urlController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'API Base URL',
                    labelStyle: const TextStyle(color: AppTheme.textSecondaryDark),
                    hintText: 'https://your-backend.onrender.com/api',
                    hintStyle: const TextStyle(color: AppTheme.textSecondaryDark, fontSize: 12),
                    prefixIcon: const Icon(Icons.link_rounded, color: AppTheme.accentOrange, size: 20),
                    filled: true,
                    fillColor: AppTheme.surfaceDark,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.borderDark),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.borderDark),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.accentOrange),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Quick Presets:',
                  style: TextStyle(
                    color: AppTheme.textSecondaryDark,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ActionChip(
                      label: const Text('Render Cloud', style: TextStyle(fontSize: 11)),
                      backgroundColor: AppTheme.surfaceDark,
                      side: const BorderSide(color: AppTheme.borderDark),
                      labelStyle: const TextStyle(color: Colors.white),
                      onPressed: () {
                        setDialogState(() {
                          urlController.text = 'https://pos-system-1-y58u.onrender.com/api';
                          testSuccess = null;
                          testMessage = null;
                        });
                      },
                    ),
                    ActionChip(
                      label: const Text('Local PC (Wi-Fi)', style: TextStyle(fontSize: 11)),
                      backgroundColor: AppTheme.surfaceDark,
                      side: const BorderSide(color: AppTheme.borderDark),
                      labelStyle: const TextStyle(color: Colors.white),
                      onPressed: () {
                        setDialogState(() {
                          urlController.text = 'http://192.168.1.5:8000/api';
                          testSuccess = null;
                          testMessage = null;
                        });
                      },
                    ),
                    ActionChip(
                      label: const Text('Emulator', style: TextStyle(fontSize: 11)),
                      backgroundColor: AppTheme.surfaceDark,
                      side: const BorderSide(color: AppTheme.borderDark),
                      labelStyle: const TextStyle(color: Colors.white),
                      onPressed: () {
                        setDialogState(() {
                          urlController.text = 'http://10.0.2.2:8000/api';
                          testSuccess = null;
                          testMessage = null;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Test Connection Button & Status
                InkWell(
                  onTap: isTesting
                      ? null
                      : () async {
                          final testUrl = urlController.text.trim();
                          if (testUrl.isEmpty) return;
                          setDialogState(() {
                            isTesting = true;
                            testSuccess = null;
                            testMessage = null;
                          });
                          final ok = await ApiService.instance.checkConnection(testUrl);
                          setDialogState(() {
                            isTesting = false;
                            testSuccess = ok;
                            testMessage = ok
                                ? 'Server is online & reachable!'
                                : 'Could not reach server. Verify connection/URL.';
                          });
                        },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: testSuccess == true
                            ? AppTheme.accentTeal.withValues(alpha: 0.5)
                            : testSuccess == false
                                ? AppTheme.accentRose.withValues(alpha: 0.5)
                                : AppTheme.borderDark,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (isTesting)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.accentOrange,
                            ),
                          )
                        else
                          Icon(
                            testSuccess == true
                                ? Icons.check_circle_rounded
                                : testSuccess == false
                                    ? Icons.error_outline_rounded
                                    : Icons.network_check_rounded,
                            size: 18,
                            color: testSuccess == true
                                ? AppTheme.accentTeal
                                : testSuccess == false
                                    ? AppTheme.accentRose
                                    : AppTheme.textSecondaryDark,
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isTesting
                                ? 'Testing connection...'
                                : testMessage ?? 'Tap here to test connection',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: testSuccess == true
                                  ? AppTheme.accentTeal
                                  : testSuccess == false
                                      ? AppTheme.accentRose
                                      : AppTheme.textSecondaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondaryDark)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentOrange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final newUrl = urlController.text.trim();
                if (newUrl.isNotEmpty) {
                  await ApiService.instance.setBaseUrl(newUrl);
                  if (mounted) setState(() {});
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Server URL set to: ${ApiService.instance.baseUrl}'),
                        backgroundColor: AppTheme.accentTeal,
                      ),
                    );
                  }
                }
              },
              child: const Text(
                'Save & Apply',
                style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
