import 'package:flutter/material.dart';

/// Shared dark palette (GitHub-ish) so pages stop inventing one-off greys.
abstract final class AppColors {
  static const bg = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22);
  static const surface2 = Color(0xFF21262D);
  static const border = Color(0xFF30363D);
  static const borderSoft = Color(0xFF21262D);
  static const text = Color(0xFFE6EDF3);
  static const textMuted = Color(0xFF8B949E);
  static const textFaint = Color(0xFF6E7681);
  static const accent = Color(0xFF2F81F7);
  static const accentSoft = Color(0xFF58A6FF);
  static const success = Color(0xFF3FB950);
  static const warning = Color(0xFFD29922);
  static const danger = Color(0xFFF85149);
  static const purple = Color(0xFFA78BFA);
  static const textCode = Color(0xFFC9D1D9);
  static const chipBlue = Color(0xFF79C0FF);
  static const slate = Color(0xFF64748B);
  static const darkBar = Color(0xFF1E1E1E);
  static const slateDeep = Color(0xFF1E293B);
  static const iconFaint = Color(0xFF484F58);
  static const dangerSoft = Color(0xFFFFB4A9);
  static const warnBright = Color(0xFFFBBF24);
  static const accentDeep = Color(0xFF1F6FEB);
  static const cyan = Color(0xFF4FC3F7);
  static const dangerAlt = Color(0xFFEF4444);
  static const warnAlt = Color(0xFFF59E0B);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    surface: AppColors.surface,
    onSurface: AppColors.text,
    primary: AppColors.accent,
    error: AppColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.bg,
    cardColor: AppColors.surface,
    dividerColor: AppColors.borderSoft,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      iconTheme: IconThemeData(color: AppColors.textMuted, size: 20),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withAlpha(0x33),
      labelTextStyle: WidgetStateProperty.resolveWith((s) {
        final selected = s.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? AppColors.accentSoft : AppColors.textMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((s) {
        final selected = s.contains(WidgetState.selected);
        return IconThemeData(
          size: 22,
          color: selected ? AppColors.accentSoft : AppColors.textMuted,
        );
      }),
      height: 64,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.textFaint),
      labelStyle: const TextStyle(color: AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accentSoft),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surface2,
      contentTextStyle: TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      titleTextStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      contentTextStyle: const TextStyle(fontSize: 14, color: AppColors.textMuted, height: 1.4),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textMuted,
      textColor: AppColors.text,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.surface,
      textStyle: TextStyle(color: AppColors.text, fontSize: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accentSoft),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) {
        return s.contains(WidgetState.selected) ? AppColors.accentSoft : AppColors.textMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((s) {
        return s.contains(WidgetState.selected)
            ? AppColors.accent.withAlpha(0x66)
            : AppColors.surface2;
      }),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accentSoft),
    iconTheme: const IconThemeData(color: AppColors.textMuted),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: AppColors.text),
      bodyMedium: TextStyle(color: AppColors.text),
      bodySmall: TextStyle(color: AppColors.textMuted),
      titleMedium: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
    ),
  );
}
