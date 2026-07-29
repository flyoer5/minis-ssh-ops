part of 'terminal_page.dart';

extension _TerminalPageWidgets on _TerminalPageState {
  Widget _buildEmptyState(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        leading: NavMenuButton.leadingOf(context),
        leadingWidth: NavMenuButton.leadingWidthOf(context),
        title: const Text('终端'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.terminal, size: 40, color: AppColors.textFaint),
              const SizedBox(height: 12),
              const Text(
                '先选择一台主机',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textMuted),
              ),
              const SizedBox(height: 6),
              const Text(
                '终端会通过 WebSocket 挂到这台主机的交互 shell。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.textFaint, height: 1.4),
              ),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: () => NavScope.maybeOf(context)?.go(0),
                icon: const Icon(Icons.dns_outlined, size: 18),
                label: const Text('去选主机'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, AppState state, String hostLabel, double fontSize) {
    return Material(
      color: _bar,
      child: Container(
        height: 36,
        padding: const EdgeInsets.only(left: 0, right: 2),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.surface2)),
        ),
        child: Row(
          children: [
            const NavMenuButton(color: AppColors.text),
            Icon(Icons.circle, size: 8, color: _connected ? AppColors.success : AppColors.danger),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: hostLabel,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.text),
                    ),
                    if (_status.isNotEmpty)
                      TextSpan(
                        text: '  $_status',
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w400),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: '减小字号',
              icon: const Icon(Icons.text_decrease, size: 16, color: AppColors.textMuted),
              onPressed: () => context.read<AppState>().setTermFontSize(fontSize - 1),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: '增大字号',
              icon: const Icon(Icons.text_increase, size: 16, color: AppColors.textMuted),
              onPressed: () => context.read<AppState>().setTermFontSize(fontSize + 1),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: _focus.hasFocus ? '收起键盘' : '键盘',
              icon: Icon(
                _focus.hasFocus ? Icons.keyboard_hide : Icons.keyboard,
                size: 18,
                color: _focus.hasFocus ? _green : AppColors.textMuted,
              ),
              onPressed: _toggleKb,
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
              color: AppColors.surface,
              onSelected: (v) async {
                switch (v) {
                  case 'paste':
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    final text = data?.text;
                    if (text == null || text.isEmpty) return;
                    _send(text.replaceAll('\n', '\r'));
                    _openKb();
                    break;
                  case 'copy_plain':
                    final plain = stripAnsi(_buf.toString());
                    await Clipboard.setData(ClipboardData(text: plain));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制纯文本'), duration: Duration(seconds: 1)),
                      );
                    }
                    break;
                  case 'copy_raw':
                    await Clipboard.setData(ClipboardData(text: _buf.toString()));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制原始输出'), duration: Duration(seconds: 1)),
                      );
                    }
                    break;
                  case 'search':
                    setState(() {
                      _showSearch = !_showSearch;
                      if (!_showSearch) {
                        _searchHits = [];
                        _searchIdx = 0;
                      }
                    });
                    break;
                  case 'clear':
                    setState(() {
                      _buf.clear();
                      _searchHits = [];
                      _searchIdx = 0;
                    });
                    break;
                  case 'reconnect':
                    _connect(state);
                    break;
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'paste', child: Text('粘贴')),
                const PopupMenuItem(value: 'copy_plain', child: Text('复制纯文本')),
                const PopupMenuItem(value: 'copy_raw', child: Text('复制原始输出')),
                PopupMenuItem(value: 'search', child: Text(_showSearch ? '关闭搜索' : '搜索回滚')),
                const PopupMenuItem(value: 'clear', child: Text('清屏')),
                const PopupMenuItem(value: 'reconnect', child: Text('重连')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Material(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '搜索终端输出',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onChanged: _runSearchDebounced,
                onSubmitted: (_) => _searchNext(),
              ),
            ),
            Text(
              _searchHits.isEmpty ? '0' : '${_searchIdx + 1}/${_searchHits.length}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace'),
            ),
            IconButton(
              tooltip: '上一个',
              visualDensity: VisualDensity.compact,
              onPressed: _searchHits.isEmpty ? null : () => _searchNext(reverse: true),
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
            ),
            IconButton(
              tooltip: '下一个',
              visualDensity: VisualDensity.compact,
              onPressed: _searchHits.isEmpty ? null : () => _searchNext(),
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
            ),
            IconButton(
              tooltip: '关闭',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() {
                _showSearch = false;
                _searchHits = [];
                _searchIdx = 0;
              }),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionBanner(AppState state) {
    if (_connecting && _hostId != null) {
      return Material(
        color: AppColors.accent.withAlpha(0x28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentSoft),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _status.isEmpty ? '连接中...' : _status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.accentSoft),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_connected && !_connecting && _hostId != null) {
      return Material(
        color: AppColors.warning.withAlpha(0x33),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.link_off, size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _status.isEmpty ? '未连接' : _status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.warning),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppColors.warning,
                ),
                onPressed: () => _connect(state),
                child: const Text('重连', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildTerminalSurface(double fontSize) {
    return Expanded(
      child: WithoutViewInsets(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openKb,
                child: Container(
                  color: _bg,
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: SelectableText.rich(
                      _buildScrollbackSpan(fontSize),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 1,
              child: Opacity(
                opacity: 0.01,
                child: EditableText(
                  controller: _input,
                  focusNode: _focus,
                  style: const TextStyle(color: Colors.transparent, fontSize: 1),
                  cursorColor: Colors.transparent,
                  backgroundCursorColor: Colors.transparent,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.newline,
                  autofocus: false,
                  enableSuggestions: false,
                  autocorrect: false,
                  onSubmitted: (_) {
                    _send('\r');
                    _input.clear();
                    _prev = '';
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
