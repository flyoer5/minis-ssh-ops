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
  static const sendGreen = Color(0xFF238636);
  static const linkFocus = Color(0xFF388BFD);
  static const userBubble = Color(0xFF2563EB);
  static const errorPanel = Color(0xFF2D1214);
  static const errorBorder = Color(0xFF6E2A2E);
  static const thinkBg = Color(0xFF12151C);
  static const thinkBorder = Color(0xFF2A3140);
  static const codeRed = Color(0xFFFF7B72);
  static const gray33 = Color(0xFF333333);
  static const gray12 = Color(0xFF121212);
  static const panelFocus = Color(0xFF1A2A33);
  static const gray66 = Color(0xFF666666);
  static const gray9e = Color(0xFF9E9E9E);
  static const grayBd = Color(0xFFBDBDBD);
  static const errPanelBg = Color(0xFF3D1F1F);
  static const errTextSoft = Color(0xFFFF8A80);
  static const selectBlue = Color(0xFF1A3A5C);
  static const folder = Color(0xFFFFB74D);
  static const fileBlue = Color(0xFF90CAF9);
  static const pureBlack = Color(0xFF0A0A0A);
  static const dividerSoft = Color(0xFF2A2A2A);
  static const slateFill = Color(0xFF0F172A);
  static const metricGreen = Color(0xFF22C55E);
  static const cardBg = Color(0xFF0F1419);
  static const selectBlue2 = Color(0xFF3B82F6);
  static const slateMuted = Color(0xFF475569);
  static const metricBlue = Color(0xFF38BDF8);
  static const metricTeal = Color(0xFF34D399);
  static const slateText = Color(0xFF94A3B8);
  static const slateBar = Color(0xFF334155);
  static const slateLine = Color(0xFFE2E8F0);
  static const riskPurple = Color(0xFFA371F7);
  static const accentMint = Color(0xFF39D353);
  static const accentPink = Color(0xFFF778BA);
  static const monoGray = Color(0xFF9CA3AF);
  static const terminalBlack = Color(0xFF000000);
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
