import 'package:flutter/material.dart';

/// Semantic palette shared across pages.
abstract final class AppColors {
  // Dark palette (GitHub dark default)
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
  static const dangerSoft = Color(0xFFFFB4A9);
  static const chipBlue = Color(0xFF79C0FF);
  static const slate = Color(0xFF64748B);
  static const iconFaint = Color(0xFF484F58);
  static const accentDeep = Color(0xFF1F6FEB);
  static const linkFocus = Color(0xFF388BFD);
  static const userBubble = Color(0xFF2563EB);
  static const errorPanel = Color(0xFF2D1214);
  static const sendGreen = Color(0xFF238636);
  static const thinkBg = Color(0xFF12151C);
  static const thinkBorder = Color(0xFF2A3140);
  static const slateDeep = Color(0xFF1E293B);
  static const slateFill = Color(0xFF0F172A);
  static const darkBar = Color(0xFF1E1E1E);
  static const terminalBlack = Color(0xFF000000);
  static const cyan = Color(0xFF4FC3F7);
  static const purple = Color(0xFFA78BFA);
  static const codeRed = Color(0xFFFF7B72);
  static const folder = Color(0xFFFFB74D);
  static const fileBlue = Color(0xFF90CAF9);
  static const metricGreen = Color(0xFF22C55E);
  static const metricBlue = Color(0xFF38BDF8);
  static const metricTeal = Color(0xFF34D399);
  static const riskPurple = Color(0xFFA371F7);
  static const accentMint = Color(0xFF39D353);
  static const accentPink = Color(0xFFF778BA);

  // Additional colors referenced by other files (kept for compatibility)
  static const textCode = Color(0xFFC9D1D9);
  static const errorBorder = Color(0xFF6E2A2E);
  static const monoGray = Color(0xFF9CA3AF);
  static const slateLine = Color(0xFFE2E8F0);
  static const warnBright = Color(0xFFFBBF24);
  static const warnAlt = Color(0xFFF59E0B);
  static const pureBlack = Color(0xFF0A0A0A);
  static const dividerSoft = Color(0xFF2A2A2A);
  static const errPanelBg = Color(0xFF3D1F1F);
  static const errTextSoft = Color(0xFFFF8A80);
  static const gray12 = Color(0xFF121212);
  static const gray33 = Color(0xFF333333);
  static const gray66 = Color(0xFF666666);
  static const gray9e = Color(0xFF9E9E9E);
  static const grayBd = Color(0xFFBDBDBD);
  static const panelFocus = Color(0xFF1A2A33);
  static const cardBg = Color(0xFF0F1419);
  static const selectBlue2 = Color(0xFF3B82F6);
  static const slateBar = Color(0xFF334155);
  static const slateMuted = Color(0xFF475569);
  static const slateText = Color(0xFF94A3B8);
  static const dangerAlt = Color(0xFFEF4444);

  // Light palette (GitHub light default)
  static const _lightBg = Color(0xFFFFFFFF);
  static const _lightSurface = Color(0xFFF6F8FA);
  static const _lightSurface2 = Color(0xFFEAEEF2);
  static const _lightBorder = Color(0xFFD1D9E0);
  static const _lightText = Color(0xFF1F2328);
  static const _lightTextMuted = Color(0xFF59636E);
  static const _lightTextFaint = Color(0xFF8C959F);
  static const _lightAccent = Color(0xFF0969DA);
  static const _lightAccentSoft = Color(0xFF0550AE);
  static const _lightSuccess = Color(0xFF1A7F37);
  static const _lightWarning = Color(0xFF9A6700);
  static const _lightDanger = Color(0xFFD1242F);
  static const _lightErrorPanel = Color(0xFFFFEBE9);
}

/// Font family constants. Avoids scattered string literals.
abstract final class AppFonts {
  static const mono = 'monospace';
  static const body = 'sans';
}

/// Theme mode preference key.
const String kThemeModeKey = 'themeMode';

ThemeData buildAppTheme({required bool dark}) {
  final scheme = dark
      ? ColorScheme.fromSeed(seedColor: AppColors.accent, brightness: Brightness.dark).copyWith(
          surface: AppColors.surface,
          onSurface: AppColors.text,
          primary: AppColors.accent,
          error: AppColors.danger,
        )
      : ColorScheme.fromSeed(seedColor: AppColors._lightAccent, brightness: Brightness.light).copyWith(
          surface: AppColors._lightSurface,
          onSurface: AppColors._lightText,
          primary: AppColors._lightAccent,
          error: AppColors._lightDanger,
        );

  final bg = dark ? AppColors.bg : AppColors._lightBg;
  final surface = dark ? AppColors.surface : AppColors._lightSurface;
  final surface2 = dark ? AppColors.surface2 : AppColors._lightSurface2;
  final border = dark ? AppColors.border : AppColors._lightBorder;
  final borderSoft = dark ? AppColors.borderSoft : AppColors._lightBorder;
  final text = dark ? AppColors.text : AppColors._lightText;
  final textMuted = dark ? AppColors.textMuted : AppColors._lightTextMuted;
  final textFaint = dark ? AppColors.textFaint : AppColors._lightTextFaint;
  final accent = dark ? AppColors.accent : AppColors._lightAccent;
  final accentSoft = dark ? AppColors.accentSoft : AppColors._lightAccentSoft;
  final danger = dark ? AppColors.danger : AppColors._lightDanger;
  final dangerSoft = dark ? AppColors.dangerSoft : const Color(0xFFFF8182);
  final errorPanel = dark ? AppColors.errorPanel : AppColors._lightErrorPanel;
  final sendGreen = dark ? AppColors.sendGreen : AppColors._lightSuccess;
  final linkFocus = dark ? AppColors.linkFocus : AppColors._lightAccentSoft;

  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    cardColor: surface,
    dividerColor: borderSoft,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text),
      iconTheme: IconThemeData(color: textMuted, size: 20),
      toolbarHeight: 48,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: accent.withAlpha(0x33),
      labelTextStyle: WidgetStateProperty.resolveWith((s) {
        final selected = s.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? accentSoft : textMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((s) {
        final selected = s.contains(WidgetState.selected);
        return IconThemeData(size: 22, color: selected ? accentSoft : textMuted);
      }),
      height: 64,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      hintStyle: TextStyle(color: textFaint),
      labelStyle: TextStyle(color: textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: linkFocus)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surface,
      contentTextStyle: TextStyle(color: text, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      insetMargin: const EdgeInsets.fromLTRB(12, 0, 12, 64),
      elevation: 4,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text),
      contentTextStyle: TextStyle(fontSize: 14, color: textMuted, height: 1.4),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent),
    listTileTheme: ListTileThemeData(iconColor: textMuted, textColor: text),
    popupMenuTheme: PopupMenuThemeData(color: surface, textStyle: TextStyle(color: text, fontSize: 14)),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white)),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: accentSoft)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accentSoft : textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent.withAlpha(0x66) : surface2),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accentSoft),
    iconTheme: IconThemeData(color: textMuted),
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: text),
      bodyMedium: TextStyle(color: text),
      bodySmall: TextStyle(color: textMuted),
      titleMedium: TextStyle(color: text, fontWeight: FontWeight.w600),
    ),
  );
}

/// Resolves semantic colors for the current brightness. Use in place of
/// direct [AppColors] references when a widget needs to adapt to light mode.
extension AdaptiveColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get bg => isDark ? AppColors.bg : AppColors._lightBg;
  Color get surface => isDark ? AppColors.surface : AppColors._lightSurface;
  Color get surface2 => isDark ? AppColors.surface2 : AppColors._lightSurface2;
  Color get border => isDark ? AppColors.border : AppColors._lightBorder;
  Color get text => isDark ? AppColors.text : AppColors._lightText;
  Color get textMuted => isDark ? AppColors.textMuted : AppColors._lightTextMuted;
  Color get textFaint => isDark ? AppColors.textFaint : AppColors._lightTextFaint;
  Color get accent => isDark ? AppColors.accent : AppColors._lightAccent;
  Color get accentSoft => isDark ? AppColors.accentSoft : AppColors._lightAccentSoft;
  Color get danger => isDark ? AppColors.danger : AppColors._lightDanger;
  Color get dangerSoft => isDark ? AppColors.dangerSoft : const Color(0xFFFF8182);
  Color get errorPanel => isDark ? AppColors.errorPanel : AppColors._lightErrorPanel;
  Color get sendGreen => isDark ? AppColors.sendGreen : AppColors._lightSuccess;
  Color get linkFocus => isDark ? AppColors.linkFocus : AppColors._lightAccentSoft;
  Color get success => isDark ? AppColors.success : AppColors._lightSuccess;
  Color get warning => isDark ? AppColors.warning : AppColors._lightWarning;
}
