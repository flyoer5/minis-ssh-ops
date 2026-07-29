part of 'files_page.dart';

extension _FilesPagePaneHelpers on _FilesPageState {
  Widget _buildPaneList(_Pane pane, int idx, double fs) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: pane.entries.length,
      itemBuilder: (context, index) {
        final raw = pane.entries[index];
        if (raw is! Map) return const SizedBox.shrink();
        final name = raw['name']?.toString() ?? raw['path']?.toString() ?? '';
        final path = raw['path']?.toString() ?? (pane.path.endsWith('/') || pane.path.isEmpty ? '${pane.path}$name' : '${pane.path}/$name');
        final isDir = raw['isDir'] == true || raw['directory'] == true || raw['type']?.toString() == 'dir';
        final selected = pane.selected.contains(path);
        return ListTile(
          dense: true,
          selected: selected,
          leading: Icon(isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined, color: isDir ? AppColors.warnBright : AppColors.textMuted),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: fs, fontFamily: isDir ? null : 'monospace')),
          trailing: pane.selecting
              ? Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? AppColors.cyan : AppColors.textFaint)
              : PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (action) {
                    if (action == 'rename') _rename(path, name);
                    if (action == 'delete') _deletePaths([path], ask: true);
                    if (action == 'copy') _copyToOther(singlePath: path);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'copy', child: Text('Copy to other pane')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
          onTap: () {
            setState(() => focus = idx);
            if (pane.selecting) {
              setState(() => selected ? pane.selected.remove(path) : pane.selected.add(path));
            } else if (isDir) {
              _go(pane, path);
            } else {
              _openFile(path);
            }
          },
          onLongPress: () => setState(() {
            focus = idx;
            pane.selecting = true;
            selected ? pane.selected.remove(path) : pane.selected.add(path);
          }),
        );
      },
    );
  }

  String _fmtSize(dynamic s) {
    final n = s is int ? s : int.tryParse('$s') ?? 0;
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} K';
    if (n < 1024 * 1024 * 1024) return '${(n / (1024 * 1024)).toStringAsFixed(1)} M';
    return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(1)} G';
  }

  Widget _pane(BuildContext context, _Pane pane, int idx, {double fontSize = 14}) {
    final fs = fontSize;
    final focused = focus == idx;
    final border = focused ? AppColors.cyan : AppColors.gray33;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => focus = idx),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.gray12,
            border: Border.all(color: border, width: focused ? 1.5 : 0.5),
          ),
          child: Column(
            children: [
              Material(
                color: focused ? AppColors.panelFocus : AppColors.darkBar,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 2, 4),
                      child: Row(
                        children: [
                          Text(
                            idx == 0 ? 'Left' : 'Right',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: focused ? AppColors.cyan : AppColors.gray66,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('~', style: TextStyle(fontSize: 13, color: AppColors.gray9e, fontFamily: 'monospace')),
                          const SizedBox(width: 4),
                          Expanded(
                            child: GestureDetector(
                              onTap: () async {
                                setState(() => focus = idx);
                                await _editPath(pane);
                              },
                              onLongPress: () async {
                                final path = pane.path.isEmpty ? '/' : pane.path;
                                await Clipboard.setData(ClipboardData(text: path));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Copied path $path'), duration: const Duration(seconds: 1)),
                                  );
                                }
                              },
                              child: Text(
                                pane.path.isEmpty ? '/' : pane.path,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: fs - 2,
                                  color: focused ? Colors.white : AppColors.grayBd,
                                  decoration: TextDecoration.underline,
                                  decorationColor: focused ? AppColors.cyan.withAlpha(0x55) : AppColors.gray66,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                            tooltip: 'Favorite path',
                            icon: Builder(
                              builder: (ctx) {
                                final s = ctx.watch<AppState>();
                                final hid = s.selectedHostId;
                                final path = pane.path.isEmpty ? '/' : pane.path;
                                final starred = hid != null && s.pathFavoritesFor(hid).contains(path);
                                return Icon(
                                  starred ? Icons.star : Icons.star_border,
                                  size: 18,
                                  color: starred ? AppColors.warnBright : null,
                                );
                              },
                            ),
                            onPressed: () async {
                              final s = context.read<AppState>();
                              final hid = s.selectedHostId;
                              if (hid == null) return;
                              final path = pane.path.isEmpty ? '/' : pane.path;
                              if (s.pathFavoritesFor(hid).contains(path)) {
                                await s.removePathFavorite(hid, path);
                              } else {
                                await s.addPathFavorite(hid, path);
                              }
                            },
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                            tooltip: 'Up',
                            icon: const Icon(Icons.arrow_upward, size: 18),
                            onPressed: () {
                              setState(() => focus = idx);
                              _up(pane);
                            },
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                            tooltip: 'Refresh',
                            icon: const Icon(Icons.refresh, size: 18),
                            onPressed: pane.loading
                                ? null
                                : () {
                                    setState(() => focus = idx);
                                    _load(pane);
                                  },
                          ),
                        ],
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final st = context.watch<AppState>();
                        final favs = st.pathFavoritesFor(st.selectedHostId);
                        if (favs.isEmpty) return const SizedBox.shrink();
                        return SizedBox(
                          height: 32,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                            itemCount: favs.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 4),
                            itemBuilder: (_, i) {
                              final p = favs[i];
                              final short = p == '/' ? '/' : (p.length > 18 ? '...${p.substring(p.length - 16)}' : p);
                              return InputChip(
                                visualDensity: VisualDensity.compact,
                                label: Text(short, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                                onPressed: () {
                                  setState(() => focus = idx);
                                  _go(pane, p);
                                },
                                onDeleted: () {
                                  final hid = st.selectedHostId;
                                  if (hid != null) st.removePathFavorite(hid, p);
                                },
                                deleteIconColor: AppColors.gray9e,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (pane.err != null)
                Material(
                  color: AppColors.errPanelBg,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(pane.err!, style: const TextStyle(color: AppColors.errTextSoft, fontSize: 11)),
                  ),
                ),
              Expanded(
                child: pane.loading
                    ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                    : pane.entries.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.folder_open, size: 36, color: Colors.white24),
                                const SizedBox(height: 8),
                                const Text('This folder is empty.', style: TextStyle(color: Colors.white38, fontSize: 13)),
                                const SizedBox(height: 4),
                                Text(
                                  pane.path.isEmpty ? '/' : pane.path,
                                  style: const TextStyle(color: Colors.white24, fontSize: 11, fontFamily: 'monospace'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 10),
                                TextButton.icon(
                                  onPressed: () => _load(pane),
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Refresh'),
                                ),
                              ],
                            ),
                          )
                        : _buildPaneList(pane, idx, fs),

              ),
            ],
          ),
        ),
      ),
    );
  }
}
