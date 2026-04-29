import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF6366F1);       // indigo-500
  static const Color primaryDark = Color(0xFF4F46E5);   // indigo-600
  static const Color primaryLight = Color(0xFFEEF2FF);  // indigo-50
  static const Color background = Color(0xFFFCFCF9);
  static const Color surface = Colors.white;
  static const Color stone50 = Color(0xFFFAFAF9);
  static const Color stone100 = Color(0xFFF5F5F4);
  static const Color stone200 = Color(0xFFE7E5E4);
  static const Color stone300 = Color(0xFFD6D3D1);
  static const Color stone400 = Color(0xFFA8A29E);
  static const Color stone500 = Color(0xFF78716C);
  static const Color stone600 = Color(0xFF57534E);
  static const Color stone700 = Color(0xFF44403C);
  static const Color stone800 = Color(0xFF292524);
  static const Color stone900 = Color(0xFF1C1917);
  static const Color error = Color(0xFFDC2626);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);

  /// Spacing scale for consistent padding/gaps across screens.
  static const double space2 = 4;
  static const double space3 = 8;
  static const double space4 = 12;
  static const double space5 = 16;
  static const double space6 = 20;
  static const double space8 = 24;
  static const double space10 = 32;

  /// Corner radii aligned with Material cards and bottom sheets.
  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 20;
  static const double radiusXl = 24;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      primaryColor: primary, // FIXED: legacy widgets that read Theme.primaryColor
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: primaryLight,
        onPrimaryContainer: primaryDark,
        surface: surface,
        onSurface: stone900,
        surfaceContainerHighest: stone100,
        error: error,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: background,
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: stone900,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: stone200,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: stone900,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: stone100),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: stone50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: stone200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: stone200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: stone400, fontFamily: 'Inter'),
        labelStyle: const TextStyle(color: stone500, fontFamily: 'Inter'),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: stone700,
          side: const BorderSide(color: stone200),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: stone100,
        surfaceTintColor: Colors.transparent,
        selectedColor: primaryLight,
        labelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: stone800,
        ),
        secondaryLabelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: stone700,
        ),
        iconTheme: const IconThemeData(color: stone700, size: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: CircleBorder(),
      ),
      dividerTheme: const DividerThemeData(
        color: stone100,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: surface,
        indicatorColor: primaryLight,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: stone900,
        contentTextStyle: const TextStyle(fontFamily: 'Inter', color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: surface,
        titleTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: stone900,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: stone700,
          height: 1.45,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        elevation: 8,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w900, color: stone900),
        displayMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: stone900),
        displaySmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: stone900),
        headlineLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: stone900),
        headlineMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: stone900),
        headlineSmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: stone900),
        titleLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: stone900),
        titleMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: stone900),
        titleSmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: stone700),
        bodyLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, color: stone800),
        bodyMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w400, color: stone700),
        bodySmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w400, color: stone500),
        labelLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: stone900),
        labelMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: stone700),
        labelSmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: stone500),
      ),
    );
  }

  // ── Dark mode palette ────────────────────────────────────────────────────
  static const Color darkBg = Color(0xFF0C0A09);
  static const Color darkSurface = Color(0xFF1C1917);
  static const Color darkCard = Color(0xFF292524);
  static const Color darkBorder = Color(0xFF44403C);
  static const Color primaryDarkMode = Color(0xFF818CF8); // lighter indigo

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      primaryColor: primaryDarkMode, // FIXED: match dark scheme primary
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primaryDarkMode,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFF3730A3),
        onPrimaryContainer: const Color(0xFFC7D2FE),
        surface: darkSurface,
        onSurface: const Color(0xFFFAFAF9),
        surfaceContainerHighest: darkCard,
        error: const Color(0xFFF87171),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: darkBg,
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: Color(0xFFFAFAF9),
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black26,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFFFAFAF9),
        ),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: darkBorder),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryDarkMode, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: stone500, fontFamily: 'Inter'),
        labelStyle: const TextStyle(color: stone400, fontFamily: 'Inter'),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryDarkMode,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFD6D3D1),
          side: const BorderSide(color: darkBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryDarkMode,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkCard,
        surfaceTintColor: Colors.transparent,
        selectedColor: const Color(0xFF3730A3),
        labelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFFFAFAF9),
        ),
        secondaryLabelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFFE7E5E4),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFD6D3D1), size: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryDarkMode,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: CircleBorder(),
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        textColor: Color(0xFFFAFAF9),
        iconColor: Color(0xFFA8A29E),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: darkSurface,
        indicatorColor: const Color(0xFF3730A3),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFFFAFAF9),
        contentTextStyle: const TextStyle(fontFamily: 'Inter', color: Color(0xFF1C1917)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: darkSurface,
        titleTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFFFAFAF9),
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: Color(0xFFD6D3D1),
          height: 1.45,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        elevation: 8,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w900, color: Color(0xFFFAFAF9)),
        displayMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Color(0xFFFAFAF9)),
        displaySmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: Color(0xFFFAFAF9)),
        headlineLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Color(0xFFFAFAF9)),
        headlineMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: Color(0xFFFAFAF9)),
        headlineSmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: Color(0xFFFAFAF9)),
        titleLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: Color(0xFFFAFAF9)),
        titleMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: Color(0xFFFAFAF9)),
        titleSmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: Color(0xFFD6D3D1)),
        bodyLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, color: Color(0xFFE7E5E4)),
        bodyMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w400, color: Color(0xFFD6D3D1)),
        bodySmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w400, color: Color(0xFFA8A29E)),
        labelLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: Color(0xFFFAFAF9)),
        labelMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: Color(0xFFD6D3D1)),
        labelSmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: Color(0xFFA8A29E)),
      ),
    );
  }
}
