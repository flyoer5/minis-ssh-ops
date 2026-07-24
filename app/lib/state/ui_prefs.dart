import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Font sizes, navigation chrome, host-card density.
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

  /// Absolute remote paths for files page shortcuts (max 12).
  List<String> pathFavorites = [];

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
    final fav = prefs.getStringList('pathFavorites') ?? const <String>[];
    pathFavorites = List<String>.from(fav);
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
        'pathFavorites': pathFavorites,
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
    if (pr['pathFavorites'] is List) {
      await setPathFavorites([
        for (final e in pr['pathFavorites'] as List)
          if (e != null && e.toString().trim().isNotEmpty) e.toString().trim(),
      ]);
    }
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

  Future<void> setPathFavorites(List<String> paths) async {
    final cleaned = <String>[];
    for (final raw in paths) {
      var p = raw.trim();
      if (p.isEmpty) continue;
      if (!p.startsWith('/')) p = '/$p';
      while (p.contains('//')) {
        p = p.replaceAll('//', '/');
      }
      if (p.length > 1 && p.endsWith('/')) p = p.substring(0, p.length - 1);
      if (!cleaned.contains(p)) cleaned.add(p);
      if (cleaned.length >= 12) break;
    }
    pathFavorites = cleaned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pathFavorites', pathFavorites);
    notifyListeners();
  }

  Future<void> addPathFavorite(String path) async {
    final list = List<String>.from(pathFavorites);
    list.remove(path);
    list.insert(0, path);
    await setPathFavorites(list);
  }

  Future<void> removePathFavorite(String path) async {
    final list = List<String>.from(pathFavorites)..remove(path);
    await setPathFavorites(list);
  }
}
