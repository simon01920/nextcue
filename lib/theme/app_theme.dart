import 'package:flutter/material.dart';

import 'tokens.dart';

/// ThemeData composed purely from tokens.dart — no new literals.
class AppTheme {
  AppTheme._();

  static TextTheme _textTheme(Color primary, Color secondary, Color muted) {
    return TextTheme(
      displayLarge: AppTextStyles.displayStat.copyWith(color: primary),
      headlineMedium: AppTextStyles.screenTitle.copyWith(color: primary),
      headlineSmall: AppTextStyles.sectionHeader.copyWith(color: primary),
      titleLarge: AppTextStyles.rowTitle.copyWith(color: primary),
      titleMedium: AppTextStyles.rowTitleList.copyWith(color: primary),
      bodyLarge: AppTextStyles.body.copyWith(color: primary),
      bodyMedium: AppTextStyles.subtitle.copyWith(color: muted),
      labelLarge: AppTextStyles.buttonPillCaps,
      labelMedium: AppTextStyles.captionCaps,
      labelSmall: AppTextStyles.microCaps,
    );
  }

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: AppTextStyles.uiFamily,
        scaffoldBackgroundColor: AppColors.bgPrimary,
        colorScheme: ColorScheme.dark(
          surface: AppColors.bgPrimary,
          surfaceContainer: AppColors.surface,
          surfaceContainerHigh: AppColors.surfaceElevated,
          primary: AppColors.accent,
          onPrimary: AppColors.accentInk,
          secondary: AppColors.link,
          onSecondary: AppColors.textPrimary,
          error: AppColors.error,
          onSurface: AppColors.textPrimary,
          outline: AppColors.borderSubtle,
        ),
        textTheme: _textTheme(
          AppColors.textPrimary,
          AppColors.textSecondary,
          AppColors.textMuted,
        ),
        dividerColor: AppColors.divider,
        dividerTheme: DividerThemeData(
          color: AppColors.divider,
          thickness: 1,
          space: 1,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.bgPrimary,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: AppTextStyles.uiFamily,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: AppColors.surfaceElevated,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg),
            ),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: AppColors.surfaceElevated,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.all(AppColors.textPrimary),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.surfaceElevated,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.accentInk,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: AppColors.errorSnackbarBg,
          contentTextStyle: TextStyle(
            fontFamily: AppTextStyles.uiFamily,
            fontSize: 15,
            color: AppColors.lightTextPrimary,
          ),
        ),
      );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: AppTextStyles.uiFamily,
        scaffoldBackgroundColor: AppColors.lightBg,
        colorScheme: const ColorScheme.light(
          surface: AppColors.lightBg,
          surfaceContainer: AppColors.lightSurface,
          surfaceContainerHigh: AppColors.lightSurface,
          primary: AppColors.accent,
          onPrimary: AppColors.accentInk,
          secondary: AppColors.link,
          error: AppColors.error,
          onSurface: AppColors.lightTextPrimary,
          outline: AppColors.lightDivider,
        ),
        textTheme: _textTheme(
          AppColors.lightTextPrimary,
          AppColors.lightTextSecondary,
          AppColors.lightTextMuted,
        ),
        dividerColor: AppColors.lightDivider,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.lightBg,
          foregroundColor: AppColors.lightTextPrimary,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: AppTextStyles.uiFamily,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.lightTextPrimary,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.accentInk,
        ),
      );
}
