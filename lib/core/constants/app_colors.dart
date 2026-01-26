import 'package:flutter/material.dart';

/// App color constants following Material Design 3
class AppColors {
  AppColors._();

  // Primary colors - Blue
  static const Color primary = Color(0xFF2196F3);
  static const Color primaryLight = Color(0xFF64B5F6);
  static const Color primaryDark = Color(0xFF1976D2);
  static const Color onPrimary = Colors.white;

  // Secondary colors - Teal
  static const Color secondary = Color(0xFF009688);
  static const Color secondaryLight = Color(0xFF4DB6AC);
  static const Color secondaryDark = Color(0xFF00796B);
  static const Color onSecondary = Colors.white;

  // Tertiary colors - Amber for accents
  static const Color tertiary = Color(0xFFFFB300);
  static const Color onTertiary = Colors.black;

  // Background colors
  static const Color backgroundLight = Color(0xFFF5F7FA);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceLight = Colors.white;
  static const Color surfaceDark = Color(0xFF1E1E1E);

  // Status colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);

  // Text colors
  static const Color textPrimaryLight = Color(0xFF212121);
  static const Color textSecondaryLight = Color(0xFF757575);
  static const Color textPrimaryDark = Color(0xFFE0E0E0);
  static const Color textSecondaryDark = Color(0xFF9E9E9E);

  // Department colors
  static const Color generalMedicine = Color(0xFF2196F3);
  static const Color dentistry = Color(0xFF9C27B0);
  static const Color psychology = Color(0xFF4CAF50);
  static const Color pharmacy = Color(0xFFFF5722);

  // Glassmorphism
  static const Color glassLight = Color(0x40FFFFFF);
  static const Color glassDark = Color(0x40000000);

  // Gradient colors
  static const List<Color> primaryGradient = [
    Color(0xFF2196F3),
    Color(0xFF1976D2),
  ];

  static const List<Color> secondaryGradient = [
    Color(0xFF009688),
    Color(0xFF00796B),
  ];

  static const List<Color> cardGradient = [
    Color(0xFF667eea),
    Color(0xFF764ba2),
  ];
}
