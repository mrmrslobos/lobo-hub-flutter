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

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
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
        selectedColor: primaryLight,
        labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600),
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

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: const Color(0xFF818CF8),
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFF3730A3),
        surface: const Color(0xFF1C1917),
        onSurface: const Color(0xFFFAFAF9),
        error: const Color(0xFFF87171),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0C0A09),
      fontFamily: 'Inter',
    );
  }
}
