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

  /// Host card: MEM+HDD only when true.
  bool hostCardCompact = false;

  bool confirmWrites = false;

  /// Absolute remote paths for files page shortcuts, keyed by host id.
  /// Legacy global list (pre-1.5.38) lives under [kPathFavShared] until a host
  /// gets its own list.
  static const kPathFavShared = '*';
  Map<String, List<String>> pathFavoritesByHost = {};

  /// When true, render assistant Markdown while tokens stream (may jitter).
  /// Default false: plain text while streaming, Markdown after final.
  bool streamMarkdown = false;

  /// Concurrent SSH probes when refreshing host list (1–6).
  int probeConcurrency = 4;

  // --- Agent ---
  /// Tool-loop rounds per user turn (1–99). Backend clamps.
  int agentMaxRounds = 12;

  /// Follow the bottom of the chat while streaming.
  bool agentAutoScroll = true;

  /// Show model "thinking / reasoning" blocks.
  bool agentShowReasoning = true;

  /// Collapse successful tool cards by default (failed still expand).
  bool agentCollapseTools = true;

  /// Enter sends message; when false, Enter inserts newline (IME action: newline).
  bool agentEnterToSend = true;

  /// Keep soft keyboard after send.
  bool agentKeepKeyboard = false;

  /// Light haptic on send / confirm run.
  bool hapticFeedback = true;

  /// LLM temperature (0.0–2.0). 0 => use backend default.
  double agentTemperature = 0;

  /// Custom system prompt suffix appended to every agent request.
  String agentCustomPrompt = '';

  /// Auto-refresh host probes in background (seconds; 0 = off).
  int hostAutoProbeSec = 0;
}
