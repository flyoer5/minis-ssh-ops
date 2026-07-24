import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';

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

  // Simple undo stack (snapshots)
  final List<String> _undo = [];
  final List<String> _redo = [];
  static const int _undoMax = 80;
  bool _applyingHistory = false;

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
      setState(() => _fontSize = s.editorFontSize.clamp(10, 24));
    });
  }

  void _syncGutterFromText() {
    if (_syncingScroll || !_gutterScroll.hasClients || !_textScroll.hasClients) return;
    _syncingScroll = true;
    if (_gutterScroll.offset != _textScroll.offset) {
      _gutterScroll.jumpTo(_textScroll.offset.clamp(
        _gutterScroll.position.minScrollExtent,
        _gutterScroll.position.maxScrollExtent,
      ));
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
      ));
    }
    _syncingScroll = false;
  }

  void _pushUndo(String before) {
    if (_applyingHistory) return;
    if (_undo.isEmpty || _undo.last != before) {
      _undo.add(before);
      if (_undo.length > _undoMax) _undo.removeAt(0);
      _redo.clear();
    }
  }

  void _undoEdit() {
    if (_undo.isEmpty || _readOnly) return;
    _applyingHistory = true;
    _redo.add(_ctrl.text);
    final prev = _undo.removeLast();
    _ctrl.value = TextEditingValue(
      text: prev,
      selection: TextSelection.collapsed(offset: prev.length.clamp(0, prev.length)),
    );
    _dirty = prev != widget.initialText;
    _applyingHistory = false;
    _updateCursorMeta();
    setState(() {});
  }

  void _redoEdit() {
    if (_redo.isEmpty || _readOnly) return;
    _applyingHistory = true;
    _undo.add(_ctrl.text);
    final next = _redo.removeLast();
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length.clamp(0, next.length)),
    );
    _dirty = next != widget.initialText;
    _applyingHistory = false;
    _updateCursorMeta();
    setState(() {});
  }

  void _onText() {
    if (_applyingHistory) {
      _updateCursorMeta();
      return;
    }
    final nowDirty = _isDirty;
    // snapshot on idle-ish edits: push previous when length jumps or selection edits
    if (nowDirty && !_dirty) {
      _pushUndo(_cleanBaseline.isEmpty ? widget.initialText : _cleanBaseline);
    }
    if (nowDirty != _dirty) {
      setState(() => _dirty = nowDirty);
    } else {
      _updateCursorMeta();
    }
    if (_showFind) _recomputeFinds();
  }

  void _updateCursorMeta() {
    final t = _ctrl.text;
    final off = _ctrl.selection.baseOffset.clamp(0, t.length);
    final before = t.substring(0, off);
    final ln = '\n'.allMatches(before).length + 1;
    final lastNl = before.lastIndexOf('\n');
    final col = lastNl < 0 ? off + 1 : off - lastNl;
    if (ln != _ln || col != _col) {
      setState(() {
        _ln = ln;
        _col = col;
      });
    }
  }

  void _recomputeFinds() {
    final q = _findCtrl.text;
    final text = _ctrl.text;
    final hits = <int>[];
    if (q.isNotEmpty) {
      final src = _findCase ? text : text.toLowerCase();
      final needle = _findCase ? q : q.toLowerCase();
      var from = 0;
      while (true) {
        final i = src.indexOf(needle, from);
        if (i < 0) break;
        hits.add(i);
        from = i + (needle.isEmpty ? 1 : needle.length);
        if (from > src.length) break;
      }
    }
    _findHits = hits;
    if (_findHits.isEmpty) {
      _findIdx = -1;
    } else if (_findIdx >= _findHits.length) {
      _findIdx = 0;
    } else if (_findIdx < 0) {
      _findIdx = 0;
    }
  }

  void _jumpFind({required bool next}) {
    if (_findHits.isEmpty) return;
    setState(() {
      if (next) {
        _findIdx = (_findIdx + 1) % _findHits.length;
      } else {
        _findIdx = (_findIdx - 1 + _findHits.length) % _findHits.length;
      }
      final start = _findHits[_findIdx];
      final end = start + _findCtrl.text.length;
      _ctrl.selection = TextSelection(baseOffset: start, extentOffset: end);
      _focus.requestFocus();
    });
    _scrollSelectionIntoView(start);
  }

  void _scrollSelectionIntoView(int offset) {
    // Approximate line-based scroll
    final before = _ctrl.text.substring(0, offset.clamp(0, _ctrl.text.length));
    final line = '\n'.allMatches(before).length;
    final y = line * _fontSize * 1.45;
    if (_textScroll.hasClients) {
      final max = _textScroll.position.maxScrollExtent;
      final target = (y - 80).clamp(0.0, max);
      _textScroll.animateTo(target, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
    }
  }

  void _replaceOne() {
    if (_readOnly || _findHits.isEmpty || _findIdx < 0) return;
    final start = _findHits[_findIdx];
    final end = start + _findCtrl.text.length;
    final before = _ctrl.text;
    _pushUndo(before);
    final next = before.replaceRange(start, end, _replaceCtrl.text);
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + _replaceCtrl.text.length),
    );
    setState(() {
      _dirty = next != widget.initialText;
      _recomputeFinds();
    });
  }

  void _replaceAll() {
    if (_readOnly || _findCtrl.text.isEmpty) return;
    final before = _ctrl.text;
    _pushUndo(before);
    String next;
    if (_findCase) {
      next = before.replaceAll(_findCtrl.text, _replaceCtrl.text);
    } else {
      // case-insensitive replace
      final re = RegExp(RegExp.escape(_findCtrl.text), caseSensitive: false);
      next = before.replaceAll(re, _replaceCtrl.text);
    }
    _ctrl.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
    setState(() {
      _dirty = next != widget.initialText;
      _recomputeFinds();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已替换'), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _save() async {
    if (_saving || _readOnly) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_ctrl.text);
      if (!mounted) return;
      // reset undo baseline? keep history
      setState(() {
        _dirty = false;
        // treat current as clean: update comparison by replacing initial via flag
      });
      // Hack: mark clean against current content by updating a local baseline
      // (widget.initialText is final — use _cleanBaseline)
      _cleanBaseline = _ctrl.text;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _cleanBaseline = '';

  bool get _isDirty {
    final base = _cleanBaseline.isEmpty ? widget.initialText : _cleanBaseline;
    return _ctrl.text != base;
  }


  Future<bool> _confirmLeave() async {
    final dirty = _isDirty;
    if (!dirty) return true;
    final a = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('未保存的更改'),
        content: const Text('离开将丢失未保存内容。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'stay'), child: const Text('继续编辑')),
          TextButton(onPressed: () => Navigator.pop(c, 'discard'), child: const Text('放弃')),
          FilledButton(
            onPressed: _readOnly ? null : () => Navigator.pop(c, 'save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (a == 'save') {
      await _save();
      return !_dirty;
    }
    return a == 'discard';
  }

  Future<void> _gotoLine() async {
    final ctrl = TextEditingController(text: '$_ln');
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('跳转到行'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(hintText: '行号'),
          onSubmitted: (s) => Navigator.pop(c, s),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('跳转')),
        ],
      ),
    );
    final n = int.tryParse((v ?? '').trim());
    if (n == null || n < 1) return;
    final parts = _ctrl.text.split('\n');
    final line = n.clamp(1, parts.length);
    var off = 0;
    for (var i = 0; i < line - 1; i++) {
      off += parts[i].length + 1;
    }
    _ctrl.selection = TextSelection.collapsed(offset: off.clamp(0, _ctrl.text.length));
    _focus.requestFocus();
    _scrollSelectionIntoView(off);
    setState(() {
      _ln = line;
      _col = 1;
    });
  }

  void _setFont(double v) {
    final next = v.clamp(10.0, 24.0);
    setState(() => _fontSize = next);
    context.read<AppState>().setEditorFontSize(next);
  }

  String _fmtSize(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} K';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} M';
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
  Widget build(BuildContext context) {
    final lines = '\n'.allMatches(_ctrl.text).length + 1;
    final lineGutterWidth = (24.0 + (lines.toString().length * (_fontSize * 0.62))).clamp(36.0, 64.0);
    final dirty = _isDirty;

    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          toolbarHeight: 48,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () async {
              if (await _confirmLeave() && mounted) Navigator.of(context).pop();
            },
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (dirty)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.circle, size: 8, color: AppColors.warnBright),
                    ),
                  Flexible(
                    child: Text(
                      _name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              Text(
                widget.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '查找/替换',
              icon: Icon(Icons.search, size: 20, color: _showFind ? AppColors.accentSoft : null),
              onPressed: () => setState(() {
                _showFind = !_showFind;
                if (_showFind) _recomputeFinds();
              }),
            ),
            IconButton(
              tooltip: '撤销',
              onPressed: _undo.isEmpty || _readOnly ? null : _undoEdit,
              icon: const Icon(Icons.undo, size: 20),
            ),
            IconButton(
              tooltip: '重做',
              onPressed: _redo.isEmpty || _readOnly ? null : _redoEdit,
              icon: const Icon(Icons.redo, size: 20),
            ),
            TextButton(
              onPressed: (!dirty || _saving || _readOnly) ? null : _save,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      _readOnly ? '只读' : '保存',
                      style: TextStyle(
                        color: (!dirty || _readOnly) ? AppColors.iconFaint : AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              icon: const Icon(Icons.more_vert, size: 20),
              color: AppColors.surface,
              onSelected: (v) async {
                switch (v) {
                  case 'goto':
                    await _gotoLine();
                    break;
                  case 'wrap':
                    setState(() => _wrap = !_wrap);
                    break;
                  case 'readonly':
                    setState(() => _readOnly = !_readOnly);
                    break;
                  case 'font_down':
                    _setFont(_fontSize - 1);
                    break;
                  case 'font_up':
                    _setFont(_fontSize + 1);
                    break;
                  case 'copy':
                    await Clipboard.setData(ClipboardData(text: _ctrl.text));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制全文'), duration: Duration(seconds: 1)),
                      );
                    }
                    break;
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'goto', child: Text('跳转到行')),
                PopupMenuItem(value: 'wrap', child: Text(_wrap ? '取消自动换行' : '自动换行')),
                PopupMenuItem(value: 'readonly', child: Text(_readOnly ? '关闭只读' : '开启只读')),
                PopupMenuItem(value: 'font_down', child: Text('减小字号 (${_fontSize.toInt()})')),
                PopupMenuItem(value: 'font_up', child: Text('增大字号')),
                const PopupMenuItem(value: 'copy', child: Text('复制全文')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            if (_showFind)
              Material(
                color: AppColors.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _findCtrl,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: '查找',
                                prefixIcon: const Icon(Icons.search, size: 18),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              ),
                              onChanged: (_) {
                                _recomputeFinds();
                                setState(() {});
                              },
                              onSubmitted: (_) => _jumpFind(next: true),
                            ),
                          ),
                          IconButton(
                            tooltip: '上一个',
                            onPressed: _findHits.isEmpty ? null : () => _jumpFind(next: false),
                            icon: const Icon(Icons.keyboard_arrow_up),
                          ),
                          IconButton(
                            tooltip: '下一个',
                            onPressed: _findHits.isEmpty ? null : () => _jumpFind(next: true),
                            icon: const Icon(Icons.keyboard_arrow_down),
                          ),
                          Text(
                            _findHits.isEmpty ? '0/0' : '${_findIdx + 1}/${_findHits.length}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _replaceCtrl,
                              enabled: !_readOnly,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: '替换为',
                                prefixIcon: const Icon(Icons.find_replace, size: 18),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              ),
                            ),
                          ),
                          TextButton(onPressed: _readOnly ? null : _replaceOne, child: const Text('替换')),
                          TextButton(onPressed: _readOnly ? null : _replaceAll, child: const Text('全部')),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          FilterChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('区分大小写', style: TextStyle(fontSize: 11)),
                            selected: _findCase,
                            onSelected: (v) {
                              setState(() {
                                _findCase = v;
                                _recomputeFinds();
                              });
                            },
                          ),
                          const Spacer(),
                          Text(
                            '字号 ${_fontSize.toInt()}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // line numbers
                  Container(
                    width: lineGutterWidth,
                    color: AppColors.bg,
                    padding: const EdgeInsets.only(top: 12, right: 6),
                    child: ListView.builder(
                      controller: _gutterScroll,
                      physics: const ClampingScrollPhysics(),
                      itemCount: lines,
                      itemBuilder: (_, i) => SizedBox(
                        height: _fontSize * 1.45,
                        child: Text(
                          '${i + 1}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: (_fontSize - 1).clamp(9, 22),
                            height: 1.45,
                            color: (i + 1) == _ln ? AppColors.textCode : AppColors.iconFaint,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, color: AppColors.surface2),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      readOnly: _readOnly,
                      maxLines: null,
                      expands: true,
                      keyboardType: TextInputType.multiline,
                      textAlignVertical: TextAlignVertical.top,
                      scrollController: _textScroll,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: _fontSize,
                        height: 1.45,
                        color: _readOnly ? AppColors.textMuted : AppColors.text,
                      ),
                      cursorColor: AppColors.accentSoft,
                      // soft wrap: when false, still wrap visually on mobile unless we use horizontal scroll —
                      // keep wrap true behavior; toggle mainly signals preference for long lines.
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.fromLTRB(10, 12, 10, 12),
                        isCollapsed: true,
                      ),
                      onTap: _updateCursorMeta,
                    ),
                  ),
                ],
              ),
            ),
            // status bar
            Container(
              height: 28,
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Text(
                    _readOnly ? '只读' : (dirty ? '已修改' : '未修改'),
                    style: TextStyle(
                      fontSize: 11,
                      color: _readOnly
                          ? AppColors.warning
                          : (dirty ? AppColors.warnBright : AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Ln $_ln, Col $_col', style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace')),
                  const SizedBox(width: 12),
                  Text('$lines 行', style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace')),
                  if (!_wrap) ...[
                    const SizedBox(width: 8),
                    const Text('不换行', style: TextStyle(fontSize: 11, color: AppColors.warning)),
                  ],
                  const Spacer(),
                  Text(_lang, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace')),
                  const SizedBox(width: 10),
                  Tooltip(
                    message: '按 UTF-8 解码/保存；其它编码请在服务端转换',
                    child: const Text(_encoding, style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace')),
                  ),
                  const SizedBox(width: 10),
                  if (widget.remoteMode != null && widget.remoteMode!.isNotEmpty) ...[
                    Text(widget.remoteMode!, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace')),
                    const SizedBox(width: 8),
                  ],
                  if (widget.remoteSize != null) ...[
                    Text(_fmtSize(widget.remoteSize!), style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace')),
                    const SizedBox(width: 8),
                  ],
                  Text('${_ctrl.text.length} 字符', style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
