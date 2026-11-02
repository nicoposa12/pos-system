import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';

class PinLoginScreen extends StatefulWidget {
  final bool isLockMode;
  const PinLoginScreen({super.key, this.isLockMode = false});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _hasError = false;
  static const int _pinLength = 4;
  late final AnimationController _shakeController;
  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        SystemChannels.textInput.invokeMethod('TextInput.hide');
        _keyboardFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _handleKeyPress(String key) {
    if (_pin.length >= _pinLength) return;
    setState(() {
      _hasError = false;
      _pin += key;
    });

    if (_pin.length == _pinLength) {
      _login();
    }
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _hasError = false;
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  void _clearPin() {
    if (_pin.isEmpty) return;
    setState(() {
      _hasError = false;
      _pin = '';
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }

    final char = event.character;
    if (char != null && RegExp(r'^[0-9]$').hasMatch(char)) {
      _handleKeyPress(char);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _login() async {
    final success = await context.read<AuthProvider>().loginWithPin(_pin);
    if (!mounted) return;

    if (success) {
      if (!widget.isLockMode && Navigator.canPop(context)) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } else {
      HapticFeedback.vibrate();
      _shakeController.forward(from: 0);
      final errorMsg = context.read<AuthProvider>().errorMessage;
      if (errorMsg != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: AppTheme.accentRose,
          ),
        );
      }
      setState(() {
        _hasError = true;
        _pin = '';
      });
    }
  }

  void _handleFooterAction() {
    if (widget.isLockMode) {
      context.read<AuthProvider>().logout();
    } else if (Navigator.canPop(context)) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } else {
      context.read<AuthProvider>().setPreferPinLogin(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Focus(
      focusNode: _keyboardFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceDark,
        resizeToAvoidBottomInset: false,
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 680;
                  final keySize = compact ? 58.0 : 68.0;
                  final rowGap = compact ? 12.0 : 16.0;

                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: compact ? 12 : 24,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(
                          0,
                          constraints.maxHeight - (compact ? 24 : 48),
                        ),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 380),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Brand / Lock Badge
                              Container(
                                width: compact ? 56 : 68,
                                height: compact ? 56 : 68,
                                decoration: BoxDecoration(
                                  color: AppTheme.cardDark,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: AppTheme.borderDark,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: widget.isLockMode
                                    ? const Icon(
                                        Icons.lock_person_rounded,
                                        color: AppTheme.accentOrange,
                                        size: 32,
                                      )
                                    : Image.asset(
                                        'assets/images/app_icon.png',
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const Icon(
                                          Icons.storefront_rounded,
                                          color: AppTheme.accentOrange,
                                          size: 32,
                                        ),
                                      ),
                              ),
                              SizedBox(height: compact ? 14 : 20),

                              // Status Pill
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentOrange.withValues(
                                    alpha: 0.14,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  widget.isLockMode
                                      ? 'REGISTER LOCKED'
                                      : 'QUICK PIN ACCESS',
                                  style: const TextStyle(
                                    color: AppTheme.accentOrange,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),

                              Text(
                                user != null && widget.isLockMode
                                    ? user.fullName
                                    : 'Enter 4-Digit PIN',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: compact ? 22 : 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _hasError
                                    ? 'Incorrect PIN. Please try again.'
                                    : (widget.isLockMode
                                          ? 'Unlock to resume your session'
                                          : 'Fast cashier sign-in'),
                                style: TextStyle(
                                  color: _hasError
                                      ? AppTheme.accentRose
                                      : AppTheme.textSecondaryDark,
                                  fontSize: 13,
                                  fontWeight: _hasError
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),

                              SizedBox(height: compact ? 20 : 28),

                              // 4-Dot PIN Indicator with Shake Animation
                              AnimatedBuilder(
                                animation: _shakeController,
                                builder: (context, child) {
                                  final dx =
                                      math.sin(
                                        _shakeController.value * math.pi * 4,
                                      ) *
                                      10 *
                                      (1 - _shakeController.value);
                                  return Transform.translate(
                                    offset: Offset(dx, 0),
                                    child: child,
                                  );
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(_pinLength, (index) {
                                    final filled = index < _pin.length;
                                    final activeColor = _hasError
                                        ? AppTheme.accentRose
                                        : AppTheme.accentOrange;

                                    return AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: filled
                                            ? activeColor
                                            : AppTheme.cardDark,
                                        border: Border.all(
                                          color: filled
                                              ? activeColor
                                              : (_hasError
                                                    ? AppTheme.accentRose
                                                          .withValues(
                                                            alpha: 0.6,
                                                          )
                                                    : AppTheme.borderDark),
                                          width: 2,
                                        ),
                                        boxShadow: filled
                                            ? [
                                                BoxShadow(
                                                  color: activeColor.withValues(
                                                    alpha: 0.35,
                                                  ),
                                                  blurRadius: 10,
                                                ),
                                              ]
                                            : const [],
                                      ),
                                    );
                                  }),
                                ),
                              ),

                              SizedBox(height: compact ? 20 : 28),

                              // Keypad Card
                              Container(
                                padding: EdgeInsets.symmetric(
                                  vertical: compact ? 18 : 24,
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.cardDark,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: AppTheme.borderDark,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    _buildKeyRow(['1', '2', '3'], keySize),
                                    SizedBox(height: rowGap),
                                    _buildKeyRow(['4', '5', '6'], keySize),
                                    SizedBox(height: rowGap),
                                    _buildKeyRow(['7', '8', '9'], keySize),
                                    SizedBox(height: rowGap),
                                    _buildKeyRow(
                                      ['clear', '0', 'backspace'],
                                      keySize,
                                    ),
                                  ],
                                ),
                              ),

                              SizedBox(height: compact ? 14 : 22),

                              // Footer Action
                              TextButton.icon(
                                onPressed: _handleFooterAction,
                                icon: Icon(
                                  widget.isLockMode
                                      ? Icons.logout_rounded
                                      : Icons.password_rounded,
                                  size: 18,
                                  color: AppTheme.textSecondaryDark,
                                ),
                                label: Text(
                                  widget.isLockMode
                                      ? 'Sign Out of Register'
                                      : 'Use Password Login',
                                  style: const TextStyle(
                                    color: AppTheme.textPrimaryDark,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyRow(List<String> keys, double keySize) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) {
        if (key == 'clear') {
          return _KeyButton(
            size: keySize,
            subtle: true,
            onPressed: _clearPin,
            child: const Text(
              'CLR',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondaryDark,
                letterSpacing: 0.6,
              ),
            ),
          );
        }
        if (key == 'backspace') {
          return _KeyButton(
            size: keySize,
            subtle: true,
            onPressed: _backspace,
            child: const Icon(
              Icons.backspace_outlined,
              color: AppTheme.textPrimaryDark,
              size: 22,
            ),
          );
        }
        return _KeyButton(
          size: keySize,
          onPressed: () => _handleKeyPress(key),
          child: Text(
            key,
            style: TextStyle(
              fontSize: keySize * 0.4,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _KeyButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;
  final double size;
  final bool subtle;

  const _KeyButton({
    required this.child,
    required this.onPressed,
    required this.size,
    this.subtle = false,
  });

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        HapticFeedback.selectionClick();
      },
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onPressed,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isPressed
                ? AppTheme.accentOrange.withValues(alpha: 0.22)
                : (widget.subtle
                      ? Colors.transparent
                      : AppTheme.surfaceDark),
            border: widget.subtle
                ? null
                : Border.all(
                    color: _isPressed
                        ? AppTheme.accentOrange
                        : AppTheme.borderDark,
                  ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
