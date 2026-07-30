import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'ui_prefs_paths.dart';
part 'ui_prefs_setters.dart';

/// Font sizes, navigation chrome, host-card density, agent behavior.
/// Mixed into [AppState] so prefs stay one notify surface for now.
mixin UiPrefs on ChangeNotifier {
  double termFontSize = 13;
  double agentFontSize = 15;
  double recordsFontSize = 13;
  double uiFontSize = 14;
  double editorFontSize = 13;

  /// bottom | menu
  String navMode = 'bottom';
  bool get navIsMenu => navMode == 'menu';
  bool get navIsBottom => !navIsMenu;

  /// Theme mode: 'system' | 'dark' | 'light'
  String themeMode = 'system';

  /// Host card: MEM+HDD only when true.
  bool hostCardCompact = false;

  bool confirmWrites = false;

  /// Absolute remote paths for files page shortcuts, keyed by host id.
  static const kPathFavShared = '*';
  Map<String, List<String>> pathFavoritesByHost = {};

  /// When true, render assistant Markdown while tokens stream (may jitter).
  bool streamMarkdown = false;

  /// Concurrent SSH probes when refreshing host list (1–6).
  int probeConcurrency = 4;

  // --- Agent ---
  int agentMaxRounds = 12;
  bool agentAutoScroll = true;
  bool agentShowReasoning = true;
  bool agentCollapseTools = true;
  bool agentEnterToSend = true;
  bool agentKeepKeyboard = false;
  bool hapticFeedback = true;
  double agentTemperature = 0;
  String agentCustomPrompt = '';
  int hostAutoProbeSec = 0;

  /// Global UI scale factor applied on top of individual font sizes (0.8–1.3).
  double uiScale = 1.0;

  /// Actual font size helpers that include [uiScale].
  double effectiveTermFontSize() => (termFontSize * uiScale).clamp(8, 28);
  double effectiveAgentFontSize() => (agentFontSize * uiScale).clamp(10, 28);
  double effectiveRecordsFontSize() => (recordsFontSize * uiScale).clamp(9, 24);
  double effectiveUiFontSize() => (uiFontSize * uiScale).clamp(9, 26);
  double effectiveEditorFontSize() => (editorFontSize * uiScale).clamp(8, 32);
}
