part of 'files_page.dart';

extension _FilesPageTransferHelpers on _FilesPageState {
  Future<void> _download(String filePath, String name) async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    setState(() {
      _transferring = true;
      _transferLabel = '正在下载 $name...';
      _transferProgress = null;
    });
    try {
      final r = await s.api.fsDownload(id, filePath);
      final b64 = r['b64']?.toString() ?? '';
      final n = r['name']?.toString() ?? name;
      final size = r['size'] ?? 0;
      if (mounted) {
        setState(() {
          _transferLabel = '下载完成 · ${_fmtSize(size)}';
          _transferProgress = 0.7;
        });
      }
      String? saved;
      try {
        saved = await NativeBackend.saveBytesToDownloads(name: n, b64: b64);
      } catch (_) {}
      if (!mounted) return;
      showSnack(context, saved != null && saved.isNotEmpty ? '已保存 $n' : '下载完成');
    } catch (e) {
      if (mounted) {
        String msg = cleanError(e);
        if (msg.toLowerCase().contains('too large') || msg.contains('file too large')) {
          msg = '文件过大，建议使用 scp 或 rsync 下载。';
        }
        showSnack(context, msg);
      }
    } finally {
      if (mounted) {
        setState(() {
          _transferring = false;
          _transferLabel = '';
          _transferProgress = null;
        });
      }
    }
  }

  Future<void> _deletePaths(Iterable<String> paths, {required bool ask}) async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null || paths.isEmpty) return;
    if (ask) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('删除 ${paths.length} 项？'),
          content: const Text('删除后无法在应用内恢复，请确认所选文件或文件夹不再需要。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
          ],
        ),
      );
      if (ok != true) return;
    }
    for (final p in paths) {
      final e = active.entries.cast<Map>().where((x) => x['path'] == p).cast<Map?>().firstWhere((_) => true, orElse: () => null);
      final isDir = e?['isDir'] == true;
      try {
        await s.api.fsRemove(id, p, recursive: isDir, confirmed: true);
      } catch (_) {}
    }
    await _load(active);
  }

  Future<void> _copyToOther({String? singlePath}) async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    final srcs = singlePath != null ? {singlePath} : Set<String>.from(active.selected);
    if (srcs.isEmpty) {
      showSnack(context, '请至少选择一项。');
      return;
    }
    final destDir = inactive.path.isEmpty ? '/' : inactive.path;
    final items = srcs.toList();
    var okN = 0;
    var failN = 0;
    var files = 0;
    var dirs = 0;
    setState(() {
      _transferring = true;
      _transferLabel = '正在复制 0/${items.length}...';
      _transferProgress = 0;
    });
    for (var i = 0; i < items.length; i++) {
      final src = items[i];
      final name = src.split('/').where((e) => e.isNotEmpty).isEmpty ? src : src.split('/').where((e) => e.isNotEmpty).last;
      final dest = destDir.endsWith('/') ? '$destDir$name' : '$destDir/$name';
      if (mounted) {
        setState(() {
          _transferLabel = '正在复制 ${i + 1}/${items.length} · $name';
          _transferProgress = i / items.length;
        });
      }
      try {
        final r = await s.api.fsCopy(id, src: src, dest: dest, confirmed: true);
        okN++;
        files += (r['files'] as num?)?.toInt() ?? 0;
        dirs += (r['dirs'] as num?)?.toInt() ?? 0;
      } catch (_) {
        failN++;
      }
    }
    if (mounted) {
      setState(() {
        _transferring = false;
        _transferLabel = '';
        _transferProgress = null;
      });
    }
    await _load(inactive);
    if (mounted) {
      final detail = files + dirs > 0 ? '（$files 个文件${dirs > 0 ? '，$dirs 个文件夹' : ''}）' : '';
      showSnack(context, failN == 0 ? '已复制 $okN 项$detail' : '复制完成：成功 $okN 项，失败 $failN 项$detail', seconds: failN == 0 ? 1 : 3);
    }
  }

  Future<void> _moveToOther() async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    final srcs = Set<String>.from(active.selected);
    if (srcs.isEmpty) {
      showSnack(context, '请至少选择一项。');
      return;
    }
    final destDir = inactive.path.isEmpty ? '/' : inactive.path;
    final items = srcs.toList();
    var okN = 0;
    var failN = 0;
    setState(() {
      _transferring = true;
      _transferLabel = '正在移动 0/${items.length}...';
      _transferProgress = 0;
    });
    for (var i = 0; i < items.length; i++) {
      final src = items[i];
      final name = src.split('/').where((e) => e.isNotEmpty).isEmpty ? src : src.split('/').where((e) => e.isNotEmpty).last;
      final dest = destDir.endsWith('/') ? '$destDir$name' : '$destDir/$name';
      if (mounted) {
        setState(() {
          _transferLabel = '正在移动 ${i + 1}/${items.length} · $name';
          _transferProgress = i / items.length;
        });
      }
      try {
        await s.api.fsMove(id, src: src, dest: dest, confirmed: true);
        okN++;
      } catch (_) {
        failN++;
      }
    }
    if (mounted) {
      setState(() {
        _transferring = false;
        _transferLabel = '';
        _transferProgress = null;
        active.selecting = false;
        active.selected.clear();
      });
    }
    await _load(active);
    await _load(inactive);
    if (mounted) {
      showSnack(context, failN == 0 ? '已移动 $okN 项' : '移动完成：成功 $okN 项，失败 $failN 项', seconds: failN == 0 ? 1 : 3);
    }
  }

  void _itemSheet(Map e) {
    final isDir = e['isDir'] == true;
    final name = e['name']?.toString() ?? '';
    final p = e['path']?.toString() ?? name;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(name), subtitle: Text(p, maxLines: 2, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
            if (!isDir)
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('打开或编辑'),
                onTap: () {
                  Navigator.pop(c);
                  _openFile(p);
                },
              ),
            if (isDir)
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('打开文件夹'),
                onTap: () {
                  Navigator.pop(c);
                  _go(active, p);
                },
              ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(c);
                _rename(p, name);
              },
            ),
            if (!isDir)
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('下载'),
                onTap: () {
                  Navigator.pop(c);
                  _download(p, name);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('删除', style: TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.pop(c);
                active.selected
                  ..clear()
                  ..add(p);
                _deletePaths([p], ask: true);
              },
            ),
          ],
        ),
      ),
    );
  }
}
