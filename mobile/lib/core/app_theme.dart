import 'package:flutter/material.dart';

/// Centralized design tokens for the Mini-Store POS app (TindaKo).
class AppTheme {
  AppTheme._();

  // ── Brand & Semantic Palette (Refined TindaKo Coral & Slate) ──
  static const Color primaryDark = Color(0xFF0F172A); // Slate 900
  static const Color accentOrange = Color(0xFFFF6B3D); // TindaKo Coral
  static const Color accentOrangeDark = Color(0xFFE85A2D);
  static const Color accentIndigo = Color(0xFF6366F1); // Secondary actions
  static const Color accentTeal = Color(0xFF10B981); // Emerald success
  static const Color accentAmber = Color(0xFFF59E0B); // Warning / Low stock
  static const Color accentRose = Color(0xFFF43F5E); // Danger / Out of stock

  // ── Neutral Surfaces & Borders ──
  static const Color surfaceLight = Color(0xFFF8FAFC); // Slate 50
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color subtleLight = Color(0xFFF1F5F9); // Slate 100
  static const Color borderLight = Color(0xFFE2E8F0); // Slate 200
  static const Color textPrimaryLight = Color(0xFF0F172A); // Slate 900
  static const Color textSecondaryLight = Color(0xFF64748B); // Slate 500

  static const Color surfaceDark = Color(0xFF0F172A); // Slate 900 (OLED-friendly)
  static const Color cardDark = Color(0xFF1E293B); // Slate 800
  static const Color subtleDark = Color(0xFF273549); // Elevated Slate
  static const Color borderDark = Color(0xFF334155); // Slate 700
  static const Color textPrimaryDark = Color(0xFFF1F5F9); // Slate 100 (anti-halation)
  static const Color textSecondaryDark = Color(0xFF94A3B8); // Slate 400

  // ── Gradient Presets ──
  static const LinearGradient orangeGradient = LinearGradient(
    colors: [Color(0xFFFF6B3D), Color(0xFFFF8C66)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroDarkGradient = LinearGradient(
    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient indigoGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient amberGradient = LinearGradient(
    colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient tealGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF34D399)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Spacing & Radii (8dp Grid) ──
  static const double paddingXs = 4.0;
  static const double paddingSm = 8.0;
  static const double paddingMd = 16.0;
  static const double paddingLg = 24.0;
  static const double paddingXl = 32.0;

  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;

  // ── Responsive Breakpoints ──
  static const double mobileBreakpoint = 600.0;
  static const double tabletBreakpoint = 840.0;
  static const double desktopBreakpoint = 1140.0;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= mobileBreakpoint;

  static bool isWidePos(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tabletBreakpoint;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopBreakpoint;

  // ── Typography Helpers ──
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  // ── Context Surface Helpers ──
  static Color borderColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? borderDark
          : borderLight;

  static Color subtleSurface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? subtleDark
          : subtleLight;

  static Color mutedText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? textSecondaryDark
          : textSecondaryLight;

  static List<BoxShadow> cardShadow(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) {
      return const [];
    }
    return [
      BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: 0.04),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ];
  }

  // ── Light Theme ──
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accentOrange,
      brightness: Brightness.light,
      primary: accentOrange,
      onPrimary: Colors.white,
      secondary: accentIndigo,
      surface: cardLight,
      onSurface: textPrimaryLight,
      error: accentRose,
    ),
    scaffoldBackgroundColor: surfaceLight,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: surfaceLight,
      surfaceTintColor: Colors.transparent,
      foregroundColor: textPrimaryLight,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: textPrimaryLight,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        side: const BorderSide(color: borderLight, width: 1),
      ),
      color: cardLight,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cardLight,
      hintStyle: const TextStyle(
        color: textSecondaryLight,
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      labelStyle: const TextStyle(
        color: textSecondaryLight,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: accentOrange, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: accentRose),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: accentRose, width: 1.8),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentOrange,
        foregroundColor: Colors.white,
        disabledBackgroundColor: borderLight,
        disabledForegroundColor: textSecondaryLight,
        elevation: 0,
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimaryLight,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: borderLight),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accentOrange,
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: cardLight,
      selectedColor: accentOrange,
      side: const BorderSide(color: borderLight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSm + 2),
      ),
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: textPrimaryLight,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: cardLight,
      surfaceTintColor: Colors.transparent,
      indicatorColor: accentOrange.withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: accentOrange,
          );
        }
        return const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textSecondaryLight,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: accentOrange, size: 24);
        }
        return const IconThemeData(color: textSecondaryLight, size: 24);
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: cardLight,
      indicatorColor: accentOrange.withValues(alpha: 0.12),
      selectedIconTheme: const IconThemeData(color: accentOrange, size: 24),
      unselectedIconTheme: const IconThemeData(color: textSecondaryLight, size: 24),
      selectedLabelTextStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: accentOrange,
      ),
      unselectedLabelTextStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: textSecondaryLight,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardLight,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXl),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: cardLight,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: borderLight,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: primaryDark,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
      ),
    ),
  );

  // ── Dark Theme ──
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accentOrange,
      brightness: Brightness.dark,
      primary: accentOrange,
      onPrimary: Colors.white,
      secondary: accentIndigo,
      surface: cardDark,
      onSurface: textPrimaryDark,
      error: accentRose,
    ),
    scaffoldBackgroundColor: surfaceDark,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: surfaceDark,
      surfaceTintColor: Colors.transparent,
      foregroundColor: textPrimaryDark,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: textPrimaryDark,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        side: const BorderSide(color: borderDark, width: 1),
      ),
      color: cardDark,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cardDark,
      hintStyle: const TextStyle(
        color: textSecondaryDark,
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      labelStyle: const TextStyle(
        color: textSecondaryDark,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: borderDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: borderDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: accentOrange, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: accentRose),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: accentRose, width: 1.8),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentOrange,
        foregroundColor: Colors.white,
        disabledBackgroundColor: borderDark,
        disabledForegroundColor: textSecondaryDark,
        elevation: 0,
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimaryDark,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: borderDark),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accentOrange,
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: cardDark,
      selectedColor: accentOrange,
      side: const BorderSide(color: borderDark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSm + 2),
      ),
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: textPrimaryDark,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: cardDark,
      surfaceTintColor: Colors.transparent,
      indicatorColor: accentOrange.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: accentOrange,
          );
        }
        return const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textSecondaryDark,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: accentOrange, size: 24);
        }
        return const IconThemeData(color: textSecondaryDark, size: 24);
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: cardDark,
      indicatorColor: accentOrange.withValues(alpha: 0.18),
      selectedIconTheme: const IconThemeData(color: accentOrange, size: 24),
      unselectedIconTheme: const IconThemeData(color: textSecondaryDark, size: 24),
      selectedLabelTextStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: accentOrange,
      ),
      unselectedLabelTextStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: textSecondaryDark,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardDark,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXl),
        side: const BorderSide(color: borderDark),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: cardDark,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: borderDark,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: subtleDark,
      contentTextStyle: const TextStyle(
        color: textPrimaryDark,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
      ),
    ),
  );
}
