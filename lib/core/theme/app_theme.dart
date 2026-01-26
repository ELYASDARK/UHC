import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

/// App theme configuration with Material Design 3
class AppTheme {
  AppTheme._();

  // Light Theme
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: _lightColorScheme,
      scaffoldBackgroundColor: AppColors.backgroundLight,
      textTheme: _textTheme,
      appBarTheme: _lightAppBarTheme,
      cardTheme: _cardTheme,
      elevatedButtonTheme: _elevatedButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme,
      textButtonTheme: _textButtonTheme,
      inputDecorationTheme: _inputDecorationTheme,
      bottomNavigationBarTheme: _lightBottomNavTheme,
      floatingActionButtonTheme: _fabTheme,
      chipTheme: _chipTheme,
      dividerTheme: _dividerTheme,
      dialogTheme: _dialogTheme,
      snackBarTheme: _snackBarTheme,
      tabBarTheme: _tabBarTheme,
    );
  }

  // Dark Theme
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: _darkColorScheme,
      scaffoldBackgroundColor: AppColors.backgroundDark,
      textTheme: _textThemeDark,
      appBarTheme: _darkAppBarTheme,
      cardTheme: _cardThemeDark,
      elevatedButtonTheme: _elevatedButtonTheme,
      outlinedButtonTheme: _outlinedButtonThemeDark,
      textButtonTheme: _textButtonTheme,
      inputDecorationTheme: _inputDecorationThemeDark,
      bottomNavigationBarTheme: _darkBottomNavTheme,
      floatingActionButtonTheme: _fabTheme,
      chipTheme: _chipThemeDark,
      dividerTheme: _dividerThemeDark,
      dialogTheme: _dialogThemeDark,
      snackBarTheme: _snackBarThemeDark,
      tabBarTheme: _tabBarThemeDark,
    );
  }

  // Color Schemes
  static const ColorScheme _lightColorScheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryLight,
    secondary: AppColors.secondary,
    onSecondary: AppColors.onSecondary,
    secondaryContainer: AppColors.secondaryLight,
    tertiary: AppColors.tertiary,
    onTertiary: AppColors.onTertiary,
    surface: AppColors.surfaceLight,
    onSurface: AppColors.textPrimaryLight,
    error: AppColors.error,
    onError: Colors.white,
  );

  static const ColorScheme _darkColorScheme = ColorScheme.dark(
    primary: AppColors.primaryLight,
    onPrimary: Colors.black,
    primaryContainer: AppColors.primaryDark,
    secondary: AppColors.secondaryLight,
    onSecondary: Colors.black,
    secondaryContainer: AppColors.secondaryDark,
    tertiary: AppColors.tertiary,
    onTertiary: AppColors.onTertiary,
    surface: AppColors.surfaceDark,
    onSurface: AppColors.textPrimaryDark,
    error: AppColors.error,
    onError: Colors.white,
  );

  // Text Theme using Google Fonts
  static TextTheme get _textTheme {
    return TextTheme(
      displayLarge: GoogleFonts.poppins(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimaryLight,
      ),
      displayMedium: GoogleFonts.poppins(
        fontSize: 45,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimaryLight,
      ),
      displaySmall: GoogleFonts.poppins(
        fontSize: 36,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimaryLight,
      ),
      headlineLarge: GoogleFonts.poppins(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryLight,
      ),
      headlineMedium: GoogleFonts.poppins(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryLight,
      ),
      headlineSmall: GoogleFonts.poppins(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryLight,
      ),
      titleLarge: GoogleFonts.poppins(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimaryLight,
      ),
      titleMedium: GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimaryLight,
      ),
      titleSmall: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimaryLight,
      ),
      bodyLarge: GoogleFonts.roboto(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimaryLight,
      ),
      bodyMedium: GoogleFonts.roboto(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimaryLight,
      ),
      bodySmall: GoogleFonts.roboto(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondaryLight,
      ),
      labelLarge: GoogleFonts.roboto(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimaryLight,
      ),
      labelMedium: GoogleFonts.roboto(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimaryLight,
      ),
      labelSmall: GoogleFonts.roboto(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondaryLight,
      ),
    );
  }

  static TextTheme get _textThemeDark {
    return TextTheme(
      displayLarge: GoogleFonts.poppins(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimaryDark,
      ),
      displayMedium: GoogleFonts.poppins(
        fontSize: 45,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimaryDark,
      ),
      displaySmall: GoogleFonts.poppins(
        fontSize: 36,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimaryDark,
      ),
      headlineLarge: GoogleFonts.poppins(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryDark,
      ),
      headlineMedium: GoogleFonts.poppins(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryDark,
      ),
      headlineSmall: GoogleFonts.poppins(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryDark,
      ),
      titleLarge: GoogleFonts.poppins(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimaryDark,
      ),
      titleMedium: GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimaryDark,
      ),
      titleSmall: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimaryDark,
      ),
      bodyLarge: GoogleFonts.roboto(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimaryDark,
      ),
      bodyMedium: GoogleFonts.roboto(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimaryDark,
      ),
      bodySmall: GoogleFonts.roboto(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondaryDark,
      ),
      labelLarge: GoogleFonts.roboto(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimaryDark,
      ),
      labelMedium: GoogleFonts.roboto(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimaryDark,
      ),
      labelSmall: GoogleFonts.roboto(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondaryDark,
      ),
    );
  }

  // AppBar Themes
  static const AppBarTheme _lightAppBarTheme = AppBarTheme(
    elevation: 0,
    centerTitle: true,
    backgroundColor: Colors.transparent,
    foregroundColor: AppColors.textPrimaryLight,
    surfaceTintColor: Colors.transparent,
  );

  static const AppBarTheme _darkAppBarTheme = AppBarTheme(
    elevation: 0,
    centerTitle: true,
    backgroundColor: Colors.transparent,
    foregroundColor: AppColors.textPrimaryDark,
    surfaceTintColor: Colors.transparent,
  );

  // Card Theme
  static CardThemeData get _cardTheme => CardThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    color: AppColors.surfaceLight,
    surfaceTintColor: Colors.transparent,
  );

  static CardThemeData get _cardThemeDark => CardThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    color: AppColors.surfaceDark,
    surfaceTintColor: Colors.transparent,
  );

  // Elevated Button Theme
  static ElevatedButtonThemeData get _elevatedButtonTheme =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  // Outlined Button Theme
  static OutlinedButtonThemeData get _outlinedButtonTheme =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(double.infinity, 56),
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  static OutlinedButtonThemeData get _outlinedButtonThemeDark =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryLight,
          minimumSize: const Size(double.infinity, 56),
          side: const BorderSide(color: AppColors.primaryLight, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  // Text Button Theme
  static TextButtonThemeData get _textButtonTheme => TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );

  // Input Decoration Theme
  static InputDecorationTheme get _inputDecorationTheme => InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surfaceLight,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.primary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.error, width: 2),
    ),
    hintStyle: GoogleFonts.roboto(
      fontSize: 14,
      color: AppColors.textSecondaryLight,
    ),
    labelStyle: GoogleFonts.roboto(
      fontSize: 14,
      color: AppColors.textSecondaryLight,
    ),
    errorStyle: GoogleFonts.roboto(fontSize: 12, color: AppColors.error),
  );

  static InputDecorationTheme get _inputDecorationThemeDark =>
      InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF424242)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        hintStyle: GoogleFonts.roboto(
          fontSize: 14,
          color: AppColors.textSecondaryDark,
        ),
        labelStyle: GoogleFonts.roboto(
          fontSize: 14,
          color: AppColors.textSecondaryDark,
        ),
        errorStyle: GoogleFonts.roboto(fontSize: 12, color: AppColors.error),
      );

  // Bottom Navigation Bar Theme
  static BottomNavigationBarThemeData get _lightBottomNavTheme =>
      const BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.surfaceLight,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondaryLight,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        elevation: 8,
      );

  static BottomNavigationBarThemeData get _darkBottomNavTheme =>
      const BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.surfaceDark,
        selectedItemColor: AppColors.primaryLight,
        unselectedItemColor: AppColors.textSecondaryDark,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        elevation: 8,
      );

  // FAB Theme
  static FloatingActionButtonThemeData get _fabTheme =>
      const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 4,
        shape: CircleBorder(),
      );

  // Chip Theme
  static ChipThemeData get _chipTheme => ChipThemeData(
    backgroundColor: AppColors.surfaceLight,
    selectedColor: AppColors.primaryLight,
    secondarySelectedColor: AppColors.primary,
    labelStyle: GoogleFonts.roboto(fontSize: 14),
    secondaryLabelStyle: GoogleFonts.roboto(fontSize: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  );

  static ChipThemeData get _chipThemeDark => ChipThemeData(
    backgroundColor: AppColors.surfaceDark,
    selectedColor: AppColors.primaryDark,
    secondarySelectedColor: AppColors.primaryLight,
    labelStyle: GoogleFonts.roboto(fontSize: 14),
    secondaryLabelStyle: GoogleFonts.roboto(fontSize: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  );

  // Divider Theme
  static const DividerThemeData _dividerTheme = DividerThemeData(
    color: Color(0xFFE0E0E0),
    thickness: 1,
    space: 1,
  );

  static const DividerThemeData _dividerThemeDark = DividerThemeData(
    color: Color(0xFF424242),
    thickness: 1,
    space: 1,
  );

  // Dialog Theme
  static DialogThemeData get _dialogTheme => DialogThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    backgroundColor: AppColors.surfaceLight,
    elevation: 8,
  );

  static DialogThemeData get _dialogThemeDark => DialogThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    backgroundColor: AppColors.surfaceDark,
    elevation: 8,
  );

  // SnackBar Theme
  static SnackBarThemeData get _snackBarTheme => SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    backgroundColor: AppColors.textPrimaryLight,
    contentTextStyle: GoogleFonts.roboto(fontSize: 14, color: Colors.white),
  );

  static SnackBarThemeData get _snackBarThemeDark => SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    backgroundColor: AppColors.surfaceLight,
    contentTextStyle: GoogleFonts.roboto(
      fontSize: 14,
      color: AppColors.textPrimaryLight,
    ),
  );

  // Tab Bar Theme
  static TabBarThemeData get _tabBarTheme => TabBarThemeData(
    indicatorColor: AppColors.primary,
    labelColor: AppColors.primary,
    unselectedLabelColor: AppColors.textSecondaryLight,
    labelStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
    unselectedLabelStyle: GoogleFonts.poppins(
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
  );

  static TabBarThemeData get _tabBarThemeDark => TabBarThemeData(
    indicatorColor: AppColors.primaryLight,
    labelColor: AppColors.primaryLight,
    unselectedLabelColor: AppColors.textSecondaryDark,
    labelStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
    unselectedLabelStyle: GoogleFonts.poppins(
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
  );
}
