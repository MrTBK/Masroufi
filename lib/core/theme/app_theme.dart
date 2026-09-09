import 'package:flutter/material.dart';

/// Centralized design system (DESIGN.md contract). No hard-coded colors,
/// sizes, or radii in widgets: everything flows from here.
/// Light-first palette generated from finance-category rules and verified
/// against WCAG AA (see DESIGN.md for ratios). Dark mode is designed, not
/// inverted.
abstract final class AppColors {
  // Brand chrome (petrol trust). Seed green kept for history only.
  static const Color seed = Color(0xFF0E7C5B); // original teal-green identity
  static const Color primary = Color(0xFF155E75);
  static const Color expense = Color(0xFFC2410C);
  static const Color income = Color(0xFF15803D);
  static const Color transfer = Color(0xFF1D4ED8);
  static const Color destructive = Color(0xFFB91C1C);
  static const Color paper = Color(0xFFFAF8F4);
  static const Color ink = Color(0xFF1C1917);
  static const Color muted = Color(0xFF57534E);
  static const Color hairline = Color(0xFFE4DED3);

  // Dark companions (desaturated, lightened; near-black warm base).
  static const Color darkBase = Color(0xFF16130F);
  static const Color darkCard = Color(0xFF1E1A15);
  static const Color darkText = Color(0xFFECE5D8);
  static const Color darkMuted = Color(0xFFA8A094);
  static const Color darkPrimary = Color(0xFF6FC7B9);
  static const Color darkOnPrimary = Color(0xFF06231F);
  static const Color darkExpense = Color(0xFFF2A37E);
  static const Color darkIncome = Color(0xFF7BD598);
  static const Color darkTransfer = Color(0xFF9DBCFF);
  static const Color darkDestructive = Color(0xFFF0978A);
  static const Color darkHairline = Color(0xFF38322A);
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md2 = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
}

/// Categorical chart palette (DESIGN.md). Chart color carries no
/// financial meaning; type stays typographic. Separate light and dark
/// ramps keep every slice legible on its background in both modes.
abstract final class AppChartColors {
  static const List<Color> light = [
    Color(0xFF0E7C5B),
    Color(0xFF1D4ED8),
    Color(0xFFC2410C),
    Color(0xFF7C3AED),
    Color(0xFFBE123C),
    Color(0xFF0E7490),
    Color(0xFFB45309),
    Color(0xFF4D7C0F),
  ];
  static const List<Color> dark = [
    Color(0xFF4DB8A4),
    Color(0xFF7FA8F5),
    Color(0xFFF0955A),
    Color(0xFFB79CFF),
    Color(0xFFF08CA0),
    Color(0xFF5CC8DC),
    Color(0xFFE8B34B),
    Color(0xFFA8C256),
  ];
}

abstract final class AppMotion {
  static const Duration press = Duration(milliseconds: 140);
  static const Duration state = Duration(milliseconds: 220);
  static const Duration sheet = Duration(milliseconds: 320);
  static const Duration navigation = Duration(milliseconds: 420);
}

TextTheme _plexType(Color ink, Color muted) {
  const family = 'PlexSans';
  TextStyle s(
    double size,
    FontWeight w,
    double height, {
    double ls = 0,
    Color? c,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: w,
    height: height,
    letterSpacing: ls,
    color: c ?? ink,
  );
  return TextTheme(
    displayLarge: s(32, FontWeight.w700, 1.15, ls: -0.5),
    displayMedium: s(28, FontWeight.w700, 1.15, ls: -0.5),
    displaySmall: s(24, FontWeight.w700, 1.15),
    headlineMedium: s(20, FontWeight.w600, 1.25),
    titleLarge: s(18, FontWeight.w600, 1.25),
    titleMedium: s(16, FontWeight.w600, 1.3),
    titleSmall: s(14, FontWeight.w600, 1.3, ls: 0.1),
    bodyLarge: s(16, FontWeight.w400, 1.5),
    bodyMedium: s(14, FontWeight.w400, 1.5),
    bodySmall: s(13, FontWeight.w400, 1.45, c: muted),
    labelLarge: s(14, FontWeight.w500, 1.3, ls: 0.2),
    labelMedium: s(13, FontWeight.w500, 1.3, ls: 0.3),
    labelSmall: s(12, FontWeight.w500, 1.3, ls: 0.3, c: muted),
  );
}

ThemeData buildLightTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.primary,
    onSecondary: Colors.white,
    tertiary: AppColors.transfer,
    onTertiary: Colors.white,
    error: AppColors.destructive,
    onError: Colors.white,
    surface: Colors.white,
    onSurface: AppColors.ink,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: AppColors.paper,
    surfaceContainer: Color(0xFFF3EEE5),
    surfaceContainerHigh: Color(0xFFEDE7DA),
    surfaceContainerHighest: Color(0xFFE4DED3),
    onSurfaceVariant: AppColors.muted,
    outline: AppColors.hairline,
    outlineVariant: AppColors.hairline,
  );
  return _themed(scheme);
}

ThemeData buildDarkTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.darkPrimary,
    onPrimary: AppColors.darkOnPrimary,
    secondary: AppColors.darkPrimary,
    onSecondary: AppColors.darkOnPrimary,
    tertiary: AppColors.darkTransfer,
    onTertiary: Color(0xFF0A1830),
    error: AppColors.darkDestructive,
    onError: Color(0xFF2A0E0B),
    surface: AppColors.darkCard,
    onSurface: AppColors.darkText,
    surfaceContainerLowest: Color(0xFF100E0B),
    surfaceContainerLow: AppColors.darkBase,
    surfaceContainer: Color(0xFF221D16),
    surfaceContainerHigh: Color(0xFF2A241B),
    surfaceContainerHighest: AppColors.darkHairline,
    onSurfaceVariant: AppColors.darkMuted,
    outline: AppColors.darkHairline,
    outlineVariant: AppColors.darkHairline,
  );
  return _themed(scheme);
}

RoundedRectangleBorder _radius(double r) => RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(r)),
);

ThemeData _themed(ColorScheme scheme) {
  final dark = scheme.brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? AppColors.darkBase : AppColors.paper,
    textTheme: _plexType(scheme.onSurface, scheme.onSurfaceVariant),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? AppColors.darkBase : AppColors.paper,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: _radius(AppRadius.md).copyWith(
        side: BorderSide(color: scheme.outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md2,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        textStyle: const TextStyle(fontFamily: 'PlexSans'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        textStyle: const TextStyle(fontFamily: 'PlexSans'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontFamily: 'PlexSans'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
        ),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outline, thickness: 1),
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: AppSpacing.sm,
      contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
    ),
  );
}
