part of 'files_page.dart';

extension _FilesPageLayout on _FilesPageState {
  Widget _buildLayout(BuildContext context) {
    final selectedId = context.select((AppState s) => s.selectedHostId);
    final backendOk = context.select((AppState s) => s.backendOk);
    // Rebuild chips/star when this host's favorites change.
    context.select((AppState s) {
      final hid = s.selectedHostId;
      return Object.hash(
        hid,
        s.pathFavoritesFor(hid).join(String.fromCharCode(0)),
      );
    });
    final state = context.read<AppState>();
    if (selectedId != null && selectedId != hostId && backendOk) {
      final next = selectedId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (next != state.selectedHostId) return;
        hostId = next;
        // Previous host's path may not exist - reset to home and clear list.
        setState(() {
          _left.path = '';
          _right.path = '';
          _left.entries = [];
          _right.entries = [];
          _left.err = null;
          _right.err = null;
          _left.selected.clear();
          _right.selected.clear();
        });
        _load(_left);
        if (dualPane) _load(_right);
      });
    }
    if (selectedId == null) return _buildNoHostScaffold(context);

    final actions = _buildActions(context);

    final fs = state.uiFontSize;
    return Scaffold(
      backgroundColor: AppColors.pureBlack,
      resizeToAvoidBottomInset: false,
      appBar: _buildAppBar(context, fs, actions),
      body: dualPane
          ? Row(
              children: [
                _pane(context, _left, 0, fontSize: fs),
                Container(width: 1, color: AppColors.dividerSoft),
                _pane(context, _right, 1, fontSize: fs),
              ],
            )
          : Row(children: [_pane(context, active, focus, fontSize: fs)]),
    );
  }

  Widget _buildNoHostScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        leading: NavMenuButton.leadingOf(context),
        leadingWidth: NavMenuButton.leadingWidthOf(context),
        title: const Text('文件', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_open, size: 40, color: AppColors.textFaint),
              const SizedBox(height: 12),
              const Text('请先选择主机', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
              const SizedBox(height: 6),
              const Text(
                '选择主机后，可浏览和编辑远程文件，并进行上传、下载和双栏操作。',
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

  List<Widget> _buildActions(BuildContext context) {
    if (active.selecting) {
      return [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '复制到另一栏',
              onPressed: active.selected.isEmpty ? null : () => _copyToOther(),
              icon: const Icon(Icons.copy_all, size: 20),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '移动到另一栏',
              onPressed: active.selected.isEmpty ? null : _moveToOther,
              icon: const Icon(Icons.drive_file_move_outline, size: 20),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert, size: 20),
              color: AppColors.darkBar,
              onSelected: (v) {
                switch (v) {
                  case 'all':
                    setState(() {
                      active.selected
                        ..clear()
                        ..addAll([
                          for (final e in active.entries)
                            if (e is Map && e['path'] != null) e['path'].toString(),
                        ]);
                    });
                    break;
                  case 'invert':
                    setState(() {
                      final all = {
                        for (final e in active.entries)
                          if (e is Map && e['path'] != null) e['path'].toString(),
                      };
                      final next = all.difference(active.selected);
                      active.selected
                        ..clear()
                        ..addAll(next);
                    });
                    break;
                  case 'delete':
                    if (active.selected.isNotEmpty) {
                      _deletePaths(active.selected, ask: true);
                    }
                    break;
                  case 'cancel':
                    setState(() {
                      active.selecting = false;
                      active.selected.clear();
                    });
                    break;
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'all',
                  enabled: active.entries.isNotEmpty,
                  child: Text('全选（${active.entries.length} 项）'),
                ),
                PopupMenuItem(
                  value: 'invert',
                  enabled: active.entries.isNotEmpty,
                  child: const Text('反选'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  enabled: active.selected.isNotEmpty,
                  child: const Text('删除选中', style: TextStyle(color: AppColors.danger)),
                ),
                const PopupMenuItem(value: 'cancel', child: Text('取消多选')),
              ],
            ),
      ];
    }
    return [
            IconButton(
              tooltip: '新建',
              onPressed: () async {
                final a = await showModalBottomSheet<String>(
                  context: context,
                  backgroundColor: AppColors.darkBar,
                  builder: (c) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.create_new_folder_outlined),
                          title: const Text('新建文件夹'),
                          onTap: () => Navigator.pop(c, 'dir'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.note_add_outlined),
                          title: const Text('新建文件'),
                          onTap: () => Navigator.pop(c, 'file'),
                        ),
                      ],
                    ),
                  ),
                );
                if (a == 'dir') await _mkdir();
                if (a == 'file') await _newFile();
              },
              icon: const Icon(Icons.add, size: 22),
            ),
            IconButton(
              tooltip: '多选',
              onPressed: () => setState(() => active.selecting = true),
              icon: const Icon(Icons.checklist, size: 20),
            ),
            IconButton(
              tooltip: dualPane ? '切换为单栏' : '切换为双栏',
              onPressed: () => setState(() => dualPane = !dualPane),
              icon: Icon(dualPane ? Icons.view_agenda_outlined : Icons.view_column_outlined, size: 20),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: active.loading ? null : () => _load(active),
              icon: const Icon(Icons.refresh, size: 20),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              icon: const Icon(Icons.more_vert, size: 20),
              color: AppColors.darkBar,
              onSelected: (v) {
                switch (v) {
                  case 'focus':
                    if (dualPane) setState(() => focus = 1 - focus);
                    break;
                  case 'swap':
                    if (dualPane) _swapPanes();
                    break;
                  case 'root':
                    _go(active, '/');
                    break;
                  case 'sort':
                    _pickSort();
                    break;
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'sort',
                  child: Text('排序：${sortBy == 'name' ? '名称' : sortBy == 'size' ? '大小' : '修改时间'}（${sortAsc ? '升序' : '降序'}）'),
                ),
                if (dualPane) const PopupMenuItem(value: 'focus', child: Text('切换当前栏')),
                if (dualPane) const PopupMenuItem(value: 'swap', child: Text('交换左右栏')),
                const PopupMenuItem(value: 'root', child: Text('返回根目录 /')),
              ],
            ),
    ];
  }

  AppBar _buildAppBar(BuildContext context, double fs, List<Widget> actions) {
    return AppBar(
      backgroundColor: AppColors.darkBar,
      toolbarHeight: 44,
      leading: NavMenuButton.leadingOf(context),
      leadingWidth: NavMenuButton.leadingWidthOf(context),
      titleSpacing: 4,
      bottom: _transferring
          ? PreferredSize(
              preferredSize: const Size.fromHeight(34),
              child: Container(
                width: double.infinity,
                color: AppColors.surface,
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _transferLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: _transferProgress,
                            minHeight: 3,
                            backgroundColor: AppColors.surface2,
                            color: AppColors.accentSoft,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: const Icon(Icons.close, size: 16, color: AppColors.textMuted),
                      tooltip: '取消传输',
                      onPressed: () {
                        setState(() {
                          _transferring = false;
                          _transferLabel = '';
                          _transferProgress = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            )
          : null,
      title: Text(
        active.selecting
            ? '已选 ${active.selected.length} 项'
            : (dualPane ? '文件 - ${focus == 0 ? "左栏" : "右栏"}' : '文件'),
        style: TextStyle(fontSize: fs + 1, fontWeight: FontWeight.w600),
      ),
      actions: actions,
    );
  }

  void _swapPanes() {
    setState(() {
      final tp = _left.path;
      final te = _left.entries;
      final terr = _left.err;
      _left.path = _right.path;
      _left.entries = _right.entries;
      _left.err = _right.err;
      _right.path = tp;
      _right.entries = te;
      _right.err = terr;
    });
  }
}
