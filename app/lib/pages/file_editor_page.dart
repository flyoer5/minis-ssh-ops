import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
import 'package:ssh_ai_agent/util/feedback.dart';

part 'file_editor_page_actions.dart';
part 'file_editor_page_layout.dart';

/// Full-screen remote text editor (MT-inspired).
class FileEditorPage extends StatefulWidget {
  final String path;
  final String initialText;
  final Future<void> Function(String text) onSave;
  final int? remoteSize;
  final String? remoteMode;

  const FileEditorPage({
    super.key,
    required this.path,
    required this.initialText,
    required this.onSave,
    this.remoteSize,
    this.remoteMode,
  });

  @override
  State<FileEditorPage> createState() => _FileEditorPageState();
}

class _FileEditorPageState extends State<FileEditorPage> {
  late final TextEditingController _ctrl;
  late final ScrollController _textScroll;
  late final ScrollController _gutterScroll;
  final _focus = FocusNode();
  final _findCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();

  bool _dirty = false;
  bool _saving = false;
  bool _showFind = false;
  bool _wrap = true;
  bool _readOnly = false;
  bool _findCase = false;
  bool _syncingScroll = false;
  static const String _encoding = 'UTF-8';
  double _fontSize = 13;
  int _ln = 1;
  int _col = 1;
  List<int> _findHits = [];
  int _findIdx = -1;

  final List<String> _undo = [];
  final List<String> _redo = [];
  static const int _undoMax = 80;
  bool _applyingHistory = false;
  String _cleanBaseline = '';

  String get _name {
    final p = widget.path;
    final i = p.lastIndexOf('/');
    return i >= 0 && i < p.length - 1 ? p.substring(i + 1) : p;
  }

  String get _lang {
    final n = _name.toLowerCase();
    if (n.endsWith('.go')) return 'Go';
    if (n.endsWith('.dart')) return 'Dart';
    if (n.endsWith('.py')) return 'Python';
    if (n.endsWith('.js') || n.endsWith('.ts') || n.endsWith('.tsx') || n.endsWith('.jsx')) return 'JS/TS';
    if (n.endsWith('.json')) return 'JSON';
    if (n.endsWith('.yml') || n.endsWith('.yaml')) return 'YAML';
    if (n.endsWith('.md')) return 'Markdown';
    if (n.endsWith('.sh') || n.endsWith('.bash')) return 'Shell';
    if (n.endsWith('.rs')) return 'Rust';
    if (n.endsWith('.java') || n.endsWith('.kt')) return 'JVM';
    if (n.endsWith('.c') || n.endsWith('.h') || n.endsWith('.cpp') || n.endsWith('.cc')) return 'C/C++';
    if (n.endsWith('.toml') || n.endsWith('.ini') || n.endsWith('.conf') || n.endsWith('.cfg')) return 'Config';
    if (n.endsWith('.xml') || n.endsWith('.html') || n.endsWith('.htm')) return 'Markup';
    if (n.endsWith('.css') || n.endsWith('.scss')) return 'CSS';
    if (n.endsWith('.sql')) return 'SQL';
    if (n.endsWith('.log') || n.endsWith('.txt')) return 'Text';
    return 'Text';
  }

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
    _textScroll = ScrollController();
    _gutterScroll = ScrollController();
    _ctrl.addListener(_onText);
    _focus.addListener(() => setState(() {}));
    _textScroll.addListener(_syncGutterFromText);
    _gutterScroll.addListener(_syncTextFromGutter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = context.read<AppState>();
      setState(() => _fontSize = s.editorFontSize.clamp(10.0, 24.0));
    });
  }

  void _syncGutterFromText() {
    if (_syncingScroll || !_gutterScroll.hasClients || !_textScroll.hasClients) return;
    _syncingScroll = true;
    if (_gutterScroll.offset != _textScroll.offset) {
      _gutterScroll.jumpTo(_textScroll.offset.clamp(
        _gutterScroll.position.minScrollExtent,
        _gutterScroll.position.maxScrollExtent,
      ).toDouble());
    }
    _syncingScroll = false;
  }

  void _syncTextFromGutter() {
    if (_syncingScroll || !_gutterScroll.hasClients || !_textScroll.hasClients) return;
    _syncingScroll = true;
    if (_textScroll.offset != _gutterScroll.offset) {
      _textScroll.jumpTo(_gutterScroll.offset.clamp(
        _textScroll.position.minScrollExtent,
        _textScroll.position.maxScrollExtent,
      ).toDouble());
    }
    _syncingScroll = false;
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onText);
    _textScroll.removeListener(_syncGutterFromText);
    _gutterScroll.removeListener(_syncTextFromGutter);
    _ctrl.dispose();
    _textScroll.dispose();
    _gutterScroll.dispose();
    _focus.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);
}
