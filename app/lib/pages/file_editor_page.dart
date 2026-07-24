import 'package:flutter/material.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
import 'package:flutter/services.dart';

/// Full-screen remote text editor (MT Manager–inspired surface).
/// From MT APK: TextEditor plugin API + find/replace/goto/undo/line numbers/encoding.
class FileEditorPage extends StatefulWidget {
  final String path;
  final String initialText;
  final Future<void> Function(String text) onSave;
  /// Optional remote size in bytes / mode string from listing.
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
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _findCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();

  bool _dirty = false;
  bool _saving = false;
  bool _showFind = false;
  bool _wrap = true;
  bool _readOnly = false;
  static const String _encoding = 'UTF-8';
  double _fontSize = 13;
  int _ln = 1;
  int _col = 1;
  int _findIdx = -1;
  final List<int> _findHits = [];

  String get _name {
    final p = widget.path;
    final i = p.lastIndexOf('/');
    return i < 0 ? p : p.substring(i + 1);
  }

  String _fmtSize(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} K';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} M';
  }

  String get _lang {
    final n = _name.toLowerCase();
    if (n.endsWith('.sh') || n.endsWith('.bash')) return 'shell';
    if (n.endsWith('.py')) return 'python';
    if (n.endsWith('.js') || n.endsWith('.ts') || n.endsWith('.tsx') || n.endsWith('.jsx')) return 'js';
    if (n.endsWith('.json')) return 'json';
    if (n.endsWith('.yml') || n.endsWith('.yaml')) return 'yaml';
    if (n.endsWith('.go')) return 'go';
    if (n.endsWith('.rs')) return 'rust';
    if (n.endsWith('.dart')) return 'dart';
    if (n.endsWith('.md')) return 'md';
    if (n.endsWith('.xml') || n.endsWith('.html') || n.endsWith('.htm')) return 'xml';
    if (n.endsWith('.css')) return 'css';
    if (n.endsWith('.java') || n.endsWith('.kt')) return 'java';
    if (n.endsWith('.c') || n.endsWith('.h') || n.endsWith('.cpp') || n.endsWith('.cc')) return 'c';
    if (n.endsWith('.conf') || n.endsWith('.ini') || n.endsWith('.toml')) return 'conf';
    return 'text';
  }

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
    _ctrl.addListener(_onText);
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onText);
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  void _onText() {
    final dirty = _ctrl.text != widget.initialText;
    final sel = _ctrl.selection;
    var ln = 1, col = 1;
    if (sel.isValid) {
      final off = sel.baseOffset.clamp(0, _ctrl.text.length);
      final before = _ctrl.text.substring(0, off);
      ln = '\n'.allMatches(before).length + 1;
      final li = before.lastIndexOf('\n');
      col = off - (li < 0 ? -1 : li);
    }
    setState(() {
      _dirty = dirty;
      _ln = ln;
      _col = col;
    });
  }

  Future<void> _save() async {
    if (_saving || _readOnly) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_ctrl.text);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      // snapshot as clean: rebind is awkward; just mark clean vs last saved
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final a = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('未保存的更改'),
        content: const Text('是否保存后再离开？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'stay'), child: const Text('继续编辑')),
          TextButton(onPressed: () => Navigator.pop(c, 'discard'), child: const Text('放弃')),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('保存')),
        ],
      ),
    );
    if (a == 'stay' || a == null) return false;
    if (a == 'discard') return true;
    await _save();
    return !_dirty;
  }

  void _recomputeFinds() {
    _findHits.clear();
    final q = _findCtrl.text;
    if (q.isEmpty) {
      _findIdx = -1;
      return;
    }
    final t = _ctrl.text;
    var from = 0;
    while (true) {
      final i = t.indexOf(q, from);
      if (i < 0) break;
      _findHits.add(i);
      from = i + q.length;
    }
    _findIdx = _findHits.isEmpty ? -1 : 0;
  }

  void _jumpFind({required bool next}) {
    if (_findHits.isEmpty) {
      _recomputeFinds();
      if (_findHits.isEmpty) {
        setState(() {});
        return;
      }
    }
    if (next) {
      _findIdx = (_findIdx + 1) % _findHits.length;
    } else {
      _findIdx = (_findIdx - 1 + _findHits.length) % _findHits.length;
    }
    final start = _findHits[_findIdx];
    final end = start + _findCtrl.text.length;
    _ctrl.selection = TextSelection(baseOffset: start, extentOffset: end);
    _focus.requestFocus();
    setState(() {});
  }

  void _replaceOne() {
    if (_findCtrl.text.isEmpty) return;
    final sel = _ctrl.selection;
    if (sel.isValid && !sel.isCollapsed && _ctrl.text.substring(sel.start, sel.end) == _findCtrl.text) {
      final t = _ctrl.text.replaceRange(sel.start, sel.end, _replaceCtrl.text);
      _ctrl.value = TextEditingValue(
        text: t,
        selection: TextSelection.collapsed(offset: sel.start + _replaceCtrl.text.length),
      );
    } else {
      _jumpFind(next: true);
      return;
    }
    _recomputeFinds();
    setState(() {});
  }

  void _replaceAll() {
    final q = _findCtrl.text;
    if (q.isEmpty) return;
    final t = _ctrl.text.replaceAll(q, _replaceCtrl.text);
    _ctrl.text = t;
    _recomputeFinds();
    setState(() {});
  }

  Future<void> _gotoLine() async {
    final ctrl = TextEditingController(text: '$_ln');
    final n = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('跳转到行'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: '行号'),
          onSubmitted: (v) => Navigator.pop(c, int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(c, int.tryParse(ctrl.text.trim())),
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    if (n == null || n < 1) return;
    final lines = _ctrl.text.split('\n');
    final target = n.clamp(1, lines.length);
    var off = 0;
    for (var i = 0; i < target - 1; i++) {
      off += lines[i].length + 1;
    }
    _ctrl.selection = TextSelection.collapsed(offset: off.clamp(0, _ctrl.text.length));
    _focus.requestFocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lines = _ctrl.text.isEmpty ? 1 : '\n'.allMatches(_ctrl.text).length + 1;
    final lineGutterWidth = 12.0 + (lines.toString().length * 8.0);

    return PopScope(
      canPop: !_dirty,
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
                  if (_dirty)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.circle, size: 8, color: AppColors.warnBright),
                    ),
                  Flexible(
                    child: Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              Text(widget.path, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: 'monospace')),
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
              tooltip: '跳转到行',
              icon: const Icon(Icons.format_list_numbered, size: 20),
              onPressed: _gotoLine,
            ),
            IconButton(
              tooltip: _wrap ? '取消换行' : '自动换行',
              icon: Icon(_wrap ? Icons.wrap_text : Icons.notes, size: 20),
              onPressed: () => setState(() => _wrap = !_wrap),
            ),
            IconButton(
              tooltip: _readOnly ? '只读（点切换）' : '可编辑（点切换只读）',
              icon: Icon(
                _readOnly ? Icons.lock_outline : Icons.lock_open_outlined,
                size: 18,
                color: _readOnly ? AppColors.warning : null,
              ),
              onPressed: () => setState(() => _readOnly = !_readOnly),
            ),
            IconButton(
              tooltip: '减小字号',
              icon: const Icon(Icons.text_decrease, size: 18),
              onPressed: () => setState(() => _fontSize = (_fontSize - 1).clamp(10, 22)),
            ),
            IconButton(
              tooltip: '增大字号',
              icon: const Icon(Icons.text_increase, size: 18),
              onPressed: () => setState(() => _fontSize = (_fontSize + 1).clamp(10, 22)),
            ),
            IconButton(
              tooltip: '复制全文',
              icon: const Icon(Icons.copy_all, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _ctrl.text));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制全文'), duration: Duration(seconds: 1)),
                  );
                }
              },
            ),
            TextButton(
              onPressed: (!_dirty || _saving || _readOnly) ? null : _save,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      _readOnly ? '只读' : '保存',
                      style: TextStyle(
                        color: (!_dirty || _readOnly) ? AppColors.iconFaint : AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
                          IconButton(tooltip: '上一个', onPressed: _findHits.isEmpty ? null : () => _jumpFind(next: false), icon: const Icon(Icons.keyboard_arrow_up)),
                          IconButton(tooltip: '下一个', onPressed: _findHits.isEmpty ? null : () => _jumpFind(next: true), icon: const Icon(Icons.keyboard_arrow_down)),
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
                          TextButton(onPressed: _replaceOne, child: const Text('替换')),
                          TextButton(onPressed: _replaceAll, child: const Text('全部')),
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
                  // line numbers gutter (MT-like)
                  Container(
                    width: lineGutterWidth,
                    color: AppColors.bg,
                    padding: const EdgeInsets.only(top: 12, right: 6),
                    child: ListView.builder(
                      controller: _scroll,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: lines,
                      itemBuilder: (_, i) => SizedBox(
                        height: _fontSize * 1.45,
                        child: Text(
                          '${i + 1}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: _fontSize - 1,
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
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: _fontSize,
                        height: 1.45,
                        color: _readOnly ? AppColors.textMuted : AppColors.text,
                      ),
                      cursorColor: AppColors.accentSoft,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.fromLTRB(10, 12, 10, 12),
                        isCollapsed: true,
                      ),
                      scrollController: _scroll,
                    ),
                  ),
                ],
              ),
            ),
            // status bar (MT-like)
            Container(
              height: 28,
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Text(
                    _readOnly ? '只读' : (_dirty ? '已修改' : '未修改'),
                    style: TextStyle(
                      fontSize: 11,
                      color: _readOnly
                          ? AppColors.warning
                          : (_dirty ? AppColors.warnBright : AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Ln $_ln, Col $_col', style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace')),
                  const SizedBox(width: 12),
                  Text('$lines 行', style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace')),
                  const Spacer(),
                  Text(_lang, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace')),
                  const SizedBox(width: 10),
                  Tooltip(
                    message: '按 UTF-8 解码/保存；其它编码请在服务端转换',
                    child: Text(_encoding, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace')),
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
