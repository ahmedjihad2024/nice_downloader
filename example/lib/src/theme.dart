import 'package:flutter/material.dart';

/// Design tokens for the download manager UI (dark theme).
abstract final class AppColors {
  static const background = Color(0xFF0E1116);
  static const surface = Color(0xFF181C24);
  static const surfaceLight = Color(0xFF222734);
  static const accent = Color(0xFF4E6AF3);
  static const textPrimary = Color(0xFFF2F4F8);
  static const textSecondary = Color(0xFF8A90A6);
  static const success = Color(0xFF34C77B);
  static const warning = Color(0xFFF5A623);
  static const danger = Color(0xFFF25555);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      surface: AppColors.surface,
      error: AppColors.danger,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.surfaceLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceLight,
      contentTextStyle: TextStyle(color: AppColors.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
