part of 'file_editor_page.dart';

extension _FileEditorPageActions on _FileEditorPageState {
  void _pushUndo(String before) {
    if (_applyingHistory) return;
    if (_undo.isEmpty || _undo.last != before) {
      _undo.add(before);
      if (_undo.length > _FileEditorPageState._undoMax) _undo.removeAt(0);
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
      selection: TextSelection.collapsed(offset: prev.length),
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
      selection: TextSelection.collapsed(offset: next.length),
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
    final off = _ctrl.selection.baseOffset.clamp(0, t.length).toInt();
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
        from = i + needle.length;
        if (from > src.length) break;
      }
    }
    _findHits = hits;
    if (_findHits.isEmpty) {
      _findIdx = -1;
    } else if (_findIdx >= _findHits.length || _findIdx < 0) {
      _findIdx = 0;
    }
  }

  void _jumpFind({required bool next}) {
    if (_findHits.isEmpty) return;
    if (next) {
      _findIdx = (_findIdx + 1) % _findHits.length;
    } else {
      _findIdx = (_findIdx - 1 + _findHits.length) % _findHits.length;
    }
    final start = _findHits[_findIdx];
    final end = start + _findCtrl.text.length;
    setState(() {
      _ctrl.selection = TextSelection(baseOffset: start, extentOffset: end);
      _focus.requestFocus();
    });
    _scrollSelectionIntoView(start);
  }

  void _scrollSelectionIntoView(int offset) {
    final before = _ctrl.text.substring(0, offset.clamp(0, _ctrl.text.length).toInt());
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
      final re = RegExp(RegExp.escape(_findCtrl.text), caseSensitive: false);
      next = before.replaceAll(re, _replaceCtrl.text);
    }
    _ctrl.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
    setState(() {
      _dirty = next != widget.initialText;
      _recomputeFinds();
    });
    showSnack(context, '已替换');
  }

  Future<void> _save() async {
    if (_saving || _readOnly) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_ctrl.text);
      if (!mounted) return;
      setState(() {
        _dirty = false;
      });
      _cleanBaseline = _ctrl.text;
      showSnack(context, '已保存');
    } catch (e) {
      if (mounted) {
        showSnack(context, '保存失败: ${cleanError(e)}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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
    final line = n.clamp(1, parts.length).toInt();
    var off = 0;
    for (var i = 0; i < line - 1; i++) {
      off += parts[i].length + 1;
    }
    _ctrl.selection = TextSelection.collapsed(offset: off.clamp(0, _ctrl.text.length).toInt());
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
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _FindIntent extends Intent {
  const _FindIntent();
}
