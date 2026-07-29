part of 'file_editor_page.dart';

extension _FileEditorPageLayout on _FileEditorPageState {
  Widget _buildPage(BuildContext context) {
    final lines = '\n'.allMatches(_ctrl.text).length + 1;
    final gutterWidth = (24.0 + lines.toString().length * (_fontSize * 0.62)).clamp(36.0, 64.0).toDouble();
    final dirty = _isDirty;

    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && await _confirmLeave() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.keyS, control: true): _SaveIntent(),
          SingleActivator(LogicalKeyboardKey.keyS, meta: true): _SaveIntent(),
          SingleActivator(LogicalKeyboardKey.keyF, control: true): _FindIntent(),
          SingleActivator(LogicalKeyboardKey.keyF, meta: true): _FindIntent(),
        },
        child: Actions(
          actions: {
            _SaveIntent: CallbackAction<_SaveIntent>(onInvoke: (_) {
              if (dirty && !_saving && !_readOnly) _save();
              return null;
            }),
            _FindIntent: CallbackAction<_FindIntent>(onInvoke: (_) {
              setState(() {
                _showFind = true;
                _recomputeFinds();
              });
              return null;
            }),
          },
          child: Focus(
            autofocus: false,
            child: Scaffold(
              backgroundColor: AppColors.bg,
              resizeToAvoidBottomInset: true,
              appBar: _buildAppBar(context, dirty),
              body: Column(
                children: [
                  if (_showFind) _buildFindBar(),
                  Expanded(child: _buildEditorBody(lines, gutterWidth)),
                  _buildStatusBar(lines, dirty),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, bool dirty) {
    return AppBar(
      backgroundColor: AppColors.surface,
      toolbarHeight: 48,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, size: 20),
        onPressed: () async {
          if (await _confirmLeave() && context.mounted) {
            Navigator.of(context).pop();
          }
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
          onSelected: (value) async {
            switch (value) {
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
                if (context.mounted) {
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
            const PopupMenuItem(value: 'font_up', child: Text('增大字号')),
            const PopupMenuItem(value: 'copy', child: Text('复制全文')),
          ],
        ),
      ],
    );
  }

  Widget _buildFindBar() {
    final count = _findHits.isEmpty ? '0/0' : '${_findIdx + 1}/${_findHits.length}';
    return Material(
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
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '查找',
                      prefixIcon: Icon(Icons.search, size: 18),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                Text(count, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace')),
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
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '替换为',
                      prefixIcon: Icon(Icons.find_replace, size: 18),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
                TextButton(onPressed: _readOnly ? null : _replaceOne, child: const Text('替换')),
                TextButton(onPressed: _readOnly ? null : _replaceAll, child: const Text('全部')),
              ],
            ),
            Row(
              children: [
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('区分大小写', style: TextStyle(fontSize: 11)),
                  selected: _findCase,
                  onSelected: (value) {
                    setState(() {
                      _findCase = value;
                      _recomputeFinds();
                    });
                  },
                ),
                const Spacer(),
                Text('字号 ${_fontSize.toInt()}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorBody(int lines, double gutterWidth) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: gutterWidth,
          color: AppColors.bg,
          padding: const EdgeInsets.only(top: 12, right: 6),
          child: ListView.builder(
            controller: _gutterScroll,
            physics: const ClampingScrollPhysics(),
            itemCount: lines,
            itemBuilder: (_, index) => SizedBox(
              height: _fontSize * 1.45,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: (_fontSize - 1).clamp(9.0, 22.0).toDouble(),
                  height: 1.45,
                  color: (index + 1) == _ln ? AppColors.textCode : AppColors.iconFaint,
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
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.fromLTRB(10, 12, 10, 12),
              isCollapsed: true,
            ),
            onTap: _updateCursorMeta,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBar(int lines, bool dirty) {
    return Container(
      height: 28,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Text(
            _readOnly ? '只读' : (dirty ? '已修改' : '未修改'),
            style: TextStyle(
              fontSize: 11,
              color: _readOnly ? AppColors.warning : (dirty ? AppColors.warnBright : AppColors.textMuted),
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
            message: '编辑器按 UTF-8 保存；其他编码请在服务端转换',
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
          const SizedBox(width: 8),
          Text('${_fontSize.toInt()}sp', style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _FindIntent extends Intent {
  const _FindIntent();
}
