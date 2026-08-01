// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

part of 'ui_prefs.dart';

extension UiPrefsSetters on UiPrefs {
  void loadUiPrefs(SharedPreferences prefs) {
    termFontSize = prefs.getDouble('termFontSize') ?? 13;
    agentFontSize = prefs.getDouble('agentFontSize') ?? 15;
    recordsFontSize = prefs.getDouble('recordsFontSize') ?? 13;
    uiFontSize = prefs.getDouble('uiFontSize') ?? 14;
    editorFontSize = prefs.getDouble('editorFontSize') ?? 13;
    confirmWrites = prefs.getBool('confirmWrites') ?? false;
    final nm = prefs.getString('navMode') ?? 'bottom';
    navMode = (nm == 'menu') ? 'menu' : 'bottom';
    themeMode = prefs.getString('themeMode') ?? 'system';
    if (themeMode != 'system' && themeMode != 'dark' && themeMode != 'light') {
      themeMode = 'system';
    }
    uiScale = (prefs.getDouble('uiScale') ?? 1.0).clamp(0.8, 1.3);
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
    final legacy = prefs.getStringList('pathFavorites');
    if (legacy != null && legacy.isNotEmpty && !pathFavoritesByHost.containsKey(UiPrefs.kPathFavShared) && pathFavoritesByHost.isEmpty) {
      pathFavoritesByHost[UiPrefs.kPathFavShared] = List<String>.from(legacy);
    }
    streamMarkdown = prefs.getBool('streamMarkdown') ?? false;
    final pc = prefs.getInt('probeConcurrency') ?? 4;
    probeConcurrency = pc.clamp(1, 6);
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
        'themeMode': themeMode,
        'uiScale': uiScale,
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
    if (pr['themeMode'] is String) await setThemeMode(pr['themeMode'] as String);
    if (pr['uiScale'] is num) await setUiScale((pr['uiScale'] as num).toDouble());
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
      await setPathFavoritesFor(UiPrefs.kPathFavShared, [for (final e in pr['pathFavorites'] as List) if (e != null && e.toString().trim().isNotEmpty) e.toString().trim()]);
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
    await setThemeMode('system');
    await setUiScale(1.0);
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
  }

  Future<void> setTermFontSize(double v) async { termFontSize = v.clamp(10, 22); final prefs = await SharedPreferences.getInstance(); await prefs.setDouble('termFontSize', termFontSize); notifyListeners(); }
  Future<void> setAgentFontSize(double v) async { agentFontSize = v.clamp(12, 22); final prefs = await SharedPreferences.getInstance(); await prefs.setDouble('agentFontSize', agentFontSize); notifyListeners(); }
  Future<void> setRecordsFontSize(double v) async { recordsFontSize = v.clamp(11, 18); final prefs = await SharedPreferences.getInstance(); await prefs.setDouble('recordsFontSize', recordsFontSize); notifyListeners(); }
  Future<void> setUiFontSize(double v) async { uiFontSize = v.clamp(11, 20); final prefs = await SharedPreferences.getInstance(); await prefs.setDouble('uiFontSize', uiFontSize); notifyListeners(); }
  Future<void> setEditorFontSize(double v) async { editorFontSize = v.clamp(10, 24); final prefs = await SharedPreferences.getInstance(); await prefs.setDouble('editorFontSize', editorFontSize); notifyListeners(); }
  Future<void> setNavMode(String mode) async { navMode = mode == 'menu' ? 'menu' : 'bottom'; final prefs = await SharedPreferences.getInstance(); await prefs.setString('navMode', navMode); notifyListeners(); }
  Future<void> setThemeMode(String mode) async { themeMode = (mode == 'dark' || mode == 'light') ? mode : 'system'; final prefs = await SharedPreferences.getInstance(); await prefs.setString('themeMode', themeMode); notifyListeners(); }
  Future<void> setUiScale(double v) async { uiScale = v.clamp(0.8, 1.3); final prefs = await SharedPreferences.getInstance(); await prefs.setDouble('uiScale', uiScale); notifyListeners(); }
  Future<void> setHostCardCompact(bool v) async { hostCardCompact = v; final prefs = await SharedPreferences.getInstance(); await prefs.setBool('hostCardCompact', hostCardCompact); notifyListeners(); }
  Future<void> setConfirmWrites(bool v) async { confirmWrites = v; final prefs = await SharedPreferences.getInstance(); await prefs.setBool('confirmWrites', v); notifyListeners(); }
  Future<void> setStreamMarkdown(bool v) async { streamMarkdown = v; final prefs = await SharedPreferences.getInstance(); await prefs.setBool('streamMarkdown', v); notifyListeners(); }
  Future<void> setProbeConcurrency(int v) async { probeConcurrency = v.clamp(1, 6); final prefs = await SharedPreferences.getInstance(); await prefs.setInt('probeConcurrency', probeConcurrency); notifyListeners(); }
  Future<void> setAgentMaxRounds(int v) async { agentMaxRounds = v.clamp(1, 99); final prefs = await SharedPreferences.getInstance(); await prefs.setInt('agentMaxRounds', agentMaxRounds); notifyListeners(); }
  Future<void> setAgentAutoScroll(bool v) async { agentAutoScroll = v; final prefs = await SharedPreferences.getInstance(); await prefs.setBool('agentAutoScroll', v); notifyListeners(); }
  Future<void> setAgentShowReasoning(bool v) async { agentShowReasoning = v; final prefs = await SharedPreferences.getInstance(); await prefs.setBool('agentShowReasoning', v); notifyListeners(); }
  Future<void> setAgentCollapseTools(bool v) async { agentCollapseTools = v; final prefs = await SharedPreferences.getInstance(); await prefs.setBool('agentCollapseTools', v); notifyListeners(); }
  Future<void> setAgentEnterToSend(bool v) async { agentEnterToSend = v; final prefs = await SharedPreferences.getInstance(); await prefs.setBool('agentEnterToSend', v); notifyListeners(); }
  Future<void> setAgentKeepKeyboard(bool v) async { agentKeepKeyboard = v; final prefs = await SharedPreferences.getInstance(); await prefs.setBool('agentKeepKeyboard', v); notifyListeners(); }
  Future<void> setHapticFeedback(bool v) async { hapticFeedback = v; final prefs = await SharedPreferences.getInstance(); await prefs.setBool('hapticFeedback', v); notifyListeners(); }
  Future<void> setAgentTemperature(double v) async { agentTemperature = v.clamp(0, 2); final prefs = await SharedPreferences.getInstance(); await prefs.setDouble('agentTemperature', agentTemperature); notifyListeners(); }
  Future<void> setAgentCustomPrompt(String v) async { agentCustomPrompt = v; final prefs = await SharedPreferences.getInstance(); await prefs.setString('agentCustomPrompt', agentCustomPrompt); notifyListeners(); }
  Future<void> setHostAutoProbeSec(int v) async { hostAutoProbeSec = v.clamp(0, 600); final prefs = await SharedPreferences.getInstance(); await prefs.setInt('hostAutoProbeSec', hostAutoProbeSec); notifyListeners(); }
}
