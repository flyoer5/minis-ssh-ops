import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Font sizes, navigation chrome, host-card density, agent behavior.
/// Mixed into [AppState] so prefs stay one notify surface for now.
mixin UiPrefs on ChangeNotifier {
  double termFontSize = 13;
  double agentFontSize = 15;
  double recordsFontSize = 13;
  double uiFontSize = 14;
  double editorFontSize = 13;

  /// `bottom` | `menu`
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

  /// Favorites for [hostId]. Falls back to shared legacy list when this host
  /// has never been customized.
  List<String> pathFavoritesFor(String? hostId) {
    if (hostId == null || hostId.isEmpty) return const [];
    final own = pathFavoritesByHost[hostId];
    if (own != null) return List<String>.from(own);
    final shared = pathFavoritesByHost[kPathFavShared];
    if (shared != null) return List<String>.from(shared);
    return const [];
  }

  /// When true, render assistant Markdown while tokens stream (may jitter).
  /// Default false: plain text while streaming, Markdown after final.
  bool streamMarkdown = false;

  /// Concurrent SSH probes when refreshing host list (1–6).
  int probeConcurrency = 4;

  // —— Agent ——
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

  /// LLM temperature (0.0–2.0). 0 → use backend default.
  double agentTemperature = 0;

  /// Custom system prompt suffix appended to every agent request.
  String agentCustomPrompt = '';

  /// Auto-refresh host probes in background (seconds; 0 = off).
  int hostAutoProbeSec = 0;

  void loadUiPrefs(SharedPreferences prefs) {
    termFontSize = prefs.getDouble('termFontSize') ?? 13;
    agentFontSize = prefs.getDouble('agentFontSize') ?? 15;
    recordsFontSize = prefs.getDouble('recordsFontSize') ?? 13;
    uiFontSize = prefs.getDouble('uiFontSize') ?? 14;
    editorFontSize = prefs.getDouble('editorFontSize') ?? 13;
    confirmWrites = prefs.getBool('confirmWrites') ?? false;
    final nm = prefs.getString('navMode') ?? 'bottom';
    navMode = (nm == 'menu') ? 'menu' : 'bottom';
    hostCardCompact = prefs.getBool('hostCardCompact') ?? false;
    pathFavoritesByHost = {};
    final byHostRaw = prefs.getString('pathFavoritesByHost');
    if (byHostRaw != null && byHostRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(byHostRaw);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            final k = e.key.toString();
            final v = e.value;
            if (v is List) {
              pathFavoritesByHost[k] = [for (final x in v) x.toString()];
            }
          }
        }
      } catch (_) {}
    }
    // Migrate pre-1.5.38 global list → shared bucket (shown until host has own).
    final legacy = prefs.getStringList('pathFavorites');
    if (legacy != null &&
        legacy.isNotEmpty &&
        !pathFavoritesByHost.containsKey(kPathFavShared) &&
        pathFavoritesByHost.isEmpty) {
      pathFavoritesByHost[kPathFavShared] = List<String>.from(legacy);
    }
    streamMarkdown = prefs.getBool('streamMarkdown') ?? false;
    final pc = prefs.getInt('probeConcurrency') ?? 4;
    probeConcurrency = pc.clamp(1, 6);

    // Migrate old low defaults: stored 5 → keep; clamp to new ceiling 32.
    agentMaxRounds = (prefs.getInt('agentMaxRounds') ?? 12).clamp(1, 99);
    agentAutoScroll = prefs.getBool('agentAutoScroll') ?? true;
    agentShowReasoning = prefs.getBool('agentShowReasoning') ?? true;
    agentCollapseTools = prefs.getBool('agentCollapseTools') ?? true;
    agentEnterToSend = prefs.getBool('agentEnterToSend') ?? true;
    agentKeepKeyboard = prefs.getBool('agentKeepKeyboard') ?? false;
    hapticFeedback = prefs.getBool('hapticFeedback') ?? true;
    agentTemperature = prefs.getDouble('agentTemperature') ?? 0;
    agentCustomPrompt = prefs.getString('agentCustomPrompt') ?? '';
    hostAutoProbeSec = (prefs.getInt('hostAutoProbeSec') ?? 0).clamp(0, 600);
  }

  Map<String, dynamic> uiPrefsExport() => {
        'termFontSize': termFontSize,
        'agentFontSize': agentFontSize,
        'recordsFontSize': recordsFontSize,
        'uiFontSize': uiFontSize,
        'editorFontSize': editorFontSize,
        'confirmWrites': confirmWrites,
        'navMode': navMode,
        'hostCardCompact': hostCardCompact,
        'pathFavoritesByHost': pathFavoritesByHost,
        'streamMarkdown': streamMarkdown,
        'probeConcurrency': probeConcurrency,
        'agentMaxRounds': agentMaxRounds,
        'agentAutoScroll': agentAutoScroll,
        'agentShowReasoning': agentShowReasoning,
        'agentCollapseTools': agentCollapseTools,
        'agentEnterToSend': agentEnterToSend,
        'agentKeepKeyboard': agentKeepKeyboard,
        'hapticFeedback': hapticFeedback,
        'agentTemperature': agentTemperature,
        'agentCustomPrompt': agentCustomPrompt,
        'hostAutoProbeSec': hostAutoProbeSec,
      };

  Future<void> applyUiPrefsImport(Map pr) async {
    if (pr['termFontSize'] is num) await setTermFontSize((pr['termFontSize'] as num).toDouble());
    if (pr['agentFontSize'] is num) await setAgentFontSize((pr['agentFontSize'] as num).toDouble());
    if (pr['recordsFontSize'] is num) await setRecordsFontSize((pr['recordsFontSize'] as num).toDouble());
    if (pr['uiFontSize'] is num) await setUiFontSize((pr['uiFontSize'] as num).toDouble());
    if (pr['editorFontSize'] is num) await setEditorFontSize((pr['editorFontSize'] as num).toDouble());
    if (pr['confirmWrites'] is bool) await setConfirmWrites(pr['confirmWrites'] as bool);
    if (pr['navMode'] is String) await setNavMode(pr['navMode'] as String);
    if (pr['hostCardCompact'] is bool) await setHostCardCompact(pr['hostCardCompact'] as bool);
    if (pr['pathFavoritesByHost'] is Map) {
      final m = <String, List<String>>{};
      for (final e in (pr['pathFavoritesByHost'] as Map).entries) {
        final v = e.value;
        if (v is List) m[e.key.toString()] = [for (final x in v) x.toString()];
      }
      pathFavoritesByHost = m;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pathFavoritesByHost', jsonEncode(pathFavoritesByHost));
      notifyListeners();
    } else if (pr['pathFavorites'] is List) {
      // Old export shape: treat as shared favorites.
      await setPathFavoritesFor(kPathFavShared, [
        for (final e in pr['pathFavorites'] as List)
          if (e != null && e.toString().trim().isNotEmpty) e.toString().trim(),
      ]);
    }
    if (pr['streamMarkdown'] is bool) await setStreamMarkdown(pr['streamMarkdown'] as bool);
    if (pr['probeConcurrency'] is num) await setProbeConcurrency((pr['probeConcurrency'] as num).toInt());
    if (pr['agentMaxRounds'] is num) await setAgentMaxRounds((pr['agentMaxRounds'] as num).toInt());
    if (pr['agentAutoScroll'] is bool) await setAgentAutoScroll(pr['agentAutoScroll'] as bool);
    if (pr['agentShowReasoning'] is bool) await setAgentShowReasoning(pr['agentShowReasoning'] as bool);
    if (pr['agentCollapseTools'] is bool) await setAgentCollapseTools(pr['agentCollapseTools'] as bool);
    if (pr['agentEnterToSend'] is bool) await setAgentEnterToSend(pr['agentEnterToSend'] as bool);
    if (pr['agentKeepKeyboard'] is bool) await setAgentKeepKeyboard(pr['agentKeepKeyboard'] as bool);
    if (pr['hapticFeedback'] is bool) await setHapticFeedback(pr['hapticFeedback'] as bool);
    if (pr['agentTemperature'] is num) await setAgentTemperature((pr['agentTemperature'] as num).toDouble());
    if (pr['agentCustomPrompt'] is String) await setAgentCustomPrompt(pr['agentCustomPrompt'] as String);
    if (pr['hostAutoProbeSec'] is num) await setHostAutoProbeSec((pr['hostAutoProbeSec'] as num).toInt());
  }

  Future<void> resetUiDefaults() async {
    await setTermFontSize(13);
    await setAgentFontSize(15);
    await setRecordsFontSize(13);
    await setUiFontSize(14);
    await setEditorFontSize(13);
    await setNavMode('bottom');
    await setHostCardCompact(false);
    await setStreamMarkdown(false);
    await setProbeConcurrency(4);
    await setAgentMaxRounds(12);
    await setAgentAutoScroll(true);
    await setAgentShowReasoning(true);
    await setAgentCollapseTools(true);
    await setAgentEnterToSend(true);
    await setAgentKeepKeyboard(false);
    await setHapticFeedback(true);
    await setAgentTemperature(0);
    await setAgentCustomPrompt('');
    await setHostAutoProbeSec(0);
    // leave confirmWrites and pathFavorites as-is (user safety / data)
  }

  Future<void> setTermFontSize(double v) async {
    termFontSize = v.clamp(10, 22);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('termFontSize', termFontSize);
    notifyListeners();
  }

  Future<void> setAgentFontSize(double v) async {
    agentFontSize = v.clamp(12, 22);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('agentFontSize', agentFontSize);
    notifyListeners();
  }

  Future<void> setRecordsFontSize(double v) async {
    recordsFontSize = v.clamp(11, 18);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('recordsFontSize', recordsFontSize);
    notifyListeners();
  }

  Future<void> setUiFontSize(double v) async {
    uiFontSize = v.clamp(11, 20);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('uiFontSize', uiFontSize);
    notifyListeners();
  }

  Future<void> setEditorFontSize(double v) async {
    editorFontSize = v.clamp(10, 24);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('editorFontSize', editorFontSize);
    notifyListeners();
  }

  Future<void> setNavMode(String mode) async {
    navMode = mode == 'menu' ? 'menu' : 'bottom';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('navMode', navMode);
    notifyListeners();
  }

  Future<void> setHostCardCompact(bool v) async {
    hostCardCompact = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hostCardCompact', hostCardCompact);
    notifyListeners();
  }

  Future<void> setConfirmWrites(bool v) async {
    confirmWrites = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('confirmWrites', v);
    notifyListeners();
  }

  static String _normPath(String raw) {
    var p = raw.trim();
    if (p.isEmpty) return '';
    if (!p.startsWith('/')) p = '/$p';
    while (p.contains('//')) {
      p = p.replaceAll('//', '/');
    }
    if (p.length > 1 && p.endsWith('/')) p = p.substring(0, p.length - 1);
    return p;
  }

  Future<void> setPathFavoritesFor(String hostId, List<String> paths) async {
    if (hostId.isEmpty) return;
    final cleaned = <String>[];
    for (final raw in paths) {
      final p = _normPath(raw);
      if (p.isEmpty) continue;
      if (!cleaned.contains(p)) cleaned.add(p);
      if (cleaned.length >= 12) break;
    }
    pathFavoritesByHost[hostId] = cleaned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pathFavoritesByHost', jsonEncode(pathFavoritesByHost));
    // Drop legacy global key once we've written the per-host map.
    await prefs.remove('pathFavorites');
    notifyListeners();
  }

  Future<void> addPathFavorite(String hostId, String path) async {
    if (hostId.isEmpty) return;
    final list = pathFavoritesFor(hostId);
    final p = _normPath(path);
    if (p.isEmpty) return;
    list.remove(p);
    list.insert(0, p);
    await setPathFavoritesFor(hostId, list);
  }

  Future<void> removePathFavorite(String hostId, String path) async {
    if (hostId.isEmpty) return;
    final list = pathFavoritesFor(hostId)..remove(_normPath(path));
    await setPathFavoritesFor(hostId, list);
  }

  Future<void> setStreamMarkdown(bool v) async {
    streamMarkdown = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('streamMarkdown', v);
    notifyListeners();
  }

  Future<void> setProbeConcurrency(int v) async {
    probeConcurrency = v.clamp(1, 6);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('probeConcurrency', probeConcurrency);
    notifyListeners();
  }

  Future<void> setAgentMaxRounds(int v) async {
    agentMaxRounds = v.clamp(1, 99);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('agentMaxRounds', agentMaxRounds);
    notifyListeners();
  }

  Future<void> setAgentAutoScroll(bool v) async {
    agentAutoScroll = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('agentAutoScroll', v);
    notifyListeners();
  }

  Future<void> setAgentShowReasoning(bool v) async {
    agentShowReasoning = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('agentShowReasoning', v);
    notifyListeners();
  }

  Future<void> setAgentCollapseTools(bool v) async {
    agentCollapseTools = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('agentCollapseTools', v);
    notifyListeners();
  }

  Future<void> setAgentEnterToSend(bool v) async {
    agentEnterToSend = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('agentEnterToSend', v);
    notifyListeners();
  }

  Future<void> setAgentKeepKeyboard(bool v) async {
    agentKeepKeyboard = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('agentKeepKeyboard', v);
    notifyListeners();
  }

  Future<void> setHapticFeedback(bool v) async {
    hapticFeedback = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hapticFeedback', v);
    notifyListeners();
  }

  Future<void> setAgentTemperature(double v) async {
    agentTemperature = v.clamp(0, 2);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('agentTemperature', agentTemperature);
    notifyListeners();
  }

  Future<void> setAgentCustomPrompt(String v) async {
    agentCustomPrompt = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('agentCustomPrompt', agentCustomPrompt);
    notifyListeners();
  }

  Future<void> setHostAutoProbeSec(int v) async {
    hostAutoProbeSec = v.clamp(0, 600);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('hostAutoProbeSec', hostAutoProbeSec);
    notifyListeners();
  }
}
