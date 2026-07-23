import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/backend/native_backend.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

/// Dual-pane remote file manager (MT Manager style).
class FilesPage extends StatefulWidget {
  const FilesPage({super.key});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _Pane {
  String path = '';
  List<dynamic> entries = [];
  bool loading = false;
  String? err;
  final Set<String> selected = {};
  bool selecting = false;
}

class _FilesPageState extends State<FilesPage> with AutomaticKeepAliveClientMixin {
  final _left = _Pane();
  final _right = _Pane();
  /// 0 = left, 1 = right
  int focus = 0;
  String? hostId;
  bool dualPane = true;

  _Pane get active => focus == 0 ? _left : _right;
  _Pane get inactive => focus == 0 ? _right : _left;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.watch<AppState>();
    if (s.selectedHostId != null && s.selectedHostId != hostId && s.backendOk) {
      hostId = s.selectedHostId;
      _load(_left);
      _load(_right);
    }
  }

  Future<void> _load(_Pane pane) async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    setState(() {
      pane.loading = true;
      pane.err = null;
      pane.selected.clear();
      pane.selecting = false;
    });
    try {
      final r = await s.api.fsList(id, pane.path);
      final list = List<dynamic>.from((r['entries'] as List?) ?? []);
      list.sort((a, b) {
        final am = a as Map, bm = b as Map;
        final ad = am['isDir'] == true, bd = bm['isDir'] == true;
        if (ad != bd) return ad ? -1 : 1;
        return (am['name']?.toString() ?? '')
            .toLowerCase()
            .compareTo((bm['name']?.toString() ?? '').toLowerCase());
      });
      setState(() {
        pane.entries = list;
        final rp = r['path']?.toString();
        if (rp != null && rp.isNotEmpty) pane.path = rp;
      });
    } catch (e) {
      setState(() => pane.err = '$e');
    } finally {
      setState(() => pane.loading = false);
    }
  }

  void _up(_Pane pane) {
    if (pane.path.isEmpty || pane.path == '/') return;
    final p = pane.path.endsWith('/') ? pane.path.substring(0, pane.path.length - 1) : pane.path;
    final i = p.lastIndexOf('/');
    setState(() => pane.path = i <= 0 ? '/' : p.substring(0, i));
    _load(pane);
  }

  void _go(_Pane pane, String p) {
    setState(() => pane.path = p);
    _load(pane);
  }

  Future<void> _openFile(String p) async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    try {
      final r = await s.api.fsRead(id, p);
      if (!mounted) return;
      final text = r['text']?.toString() ?? '';
      final ctrl = TextEditingController(text: text);
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(p.split('/').last, style: const TextStyle(fontSize: 14)),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: TextField(
              controller: ctrl,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('关闭')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
          ],
        ),
      );
      if (ok == true) {
        await s.api.fsWrite(id, p, ctrl.text, confirmed: true);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
        await _load(active);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _mkdir() async {
    final pane = active;
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: '名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('创建')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final base = pane.path;
    final full = base.endsWith('/') || base.isEmpty ? '$base$name' : '$base/$name';
    try {
      await s.api.fsMkdir(id, full, confirmed: true);
      await _load(pane);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _newFile() async {
    final pane = active;
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    final nameCtrl = TextEditingController(text: 'note.txt');
    final bodyCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('新建文件'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '文件名')),
              TextField(controller: bodyCtrl, maxLines: 6, decoration: const InputDecoration(labelText: '内容')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final base = pane.path;
    final full = base.endsWith('/') || base.isEmpty ? '$base$name' : '$base/$name';
    try {
      await s.api.fsWrite(id, full, bodyCtrl.text, confirmed: true);
      await _load(pane);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _rename(String oldPath, String oldName) async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    final ctrl = TextEditingController(text: oldName);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(controller: ctrl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('确定')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == oldName) return;
    final slash = oldPath.lastIndexOf('/');
    final parent = slash <= 0 ? '' : oldPath.substring(0, slash);
    final newPath = parent.isEmpty ? name : '$parent/$name';
    try {
      await s.api.fsRename(id, oldPath, newPath, confirmed: true);
      await _load(active);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _download(String filePath, String name) async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    try {
      final r = await s.api.fsDownload(id, filePath);
      final b64 = r['b64']?.toString() ?? '';
      final n = r['name']?.toString() ?? name;
      final size = r['size'] ?? 0;
      String? saved;
      try {
        saved = await NativeBackend.saveBytesToDownloads(name: n, b64: b64);
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saved != null ? '已保存 $size 字节' : '下载失败，可稍后重试')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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

  /// Copy selected (or one path) from focus pane into the other pane path via read+write (files only).
  Future<void> _copyToOther({String? singlePath}) async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    final srcs = singlePath != null ? {singlePath} : Set<String>.from(active.selected);
    if (srcs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先选中文件（多选）')));
      return;
    }
    final destDir = inactive.path;
    var n = 0;
    for (final src in srcs) {
      final e = active.entries.cast<Map>().where((x) => x['path'] == src).cast<Map?>().firstWhere((_) => true, orElse: () => null);
      if (e == null) continue;
      if (e['isDir'] == true) {
        // skip dirs for simple copy (no recursive copy API yet)
        continue;
      }
      final name = e['name']?.toString() ?? src.split('/').last;
      final dest = destDir.endsWith('/') || destDir.isEmpty ? '$destDir$name' : '$destDir/$name';
      try {
        final r = await s.api.fsRead(id, src);
        final text = r['text']?.toString() ?? '';
        await s.api.fsWrite(id, dest, text, confirmed: true);
        n++;
      } catch (_) {}
    }
    await _load(inactive);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制 $n 个文件到另一栏')));
    }
  }

  Future<void> _moveToOther() async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    final srcs = Set<String>.from(active.selected);
    if (srcs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先多选项目')));
      return;
    }
    final destDir = inactive.path;
    var n = 0;
    for (final src in srcs) {
      final name = src.split('/').last;
      final dest = destDir.endsWith('/') || destDir.isEmpty ? '$destDir$name' : '$destDir/$name';
      try {
        await s.api.fsRename(id, src, dest, confirmed: true);
        n++;
      } catch (_) {}
    }
    await _load(active);
    await _load(inactive);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已移动 $n 项')));
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
                title: const Text('打开 / 编辑'),
                onTap: () {
                  Navigator.pop(c);
                  _openFile(p);
                },
              ),
            if (isDir)
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('进入'),
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
                title: const Text('下载到手机'),
                onTap: () {
                  Navigator.pop(c);
                  _download(p, name);
                },
              ),
            if (!isDir)
              ListTile(
                leading: const Icon(Icons.copy_all),
                title: const Text('复制到另一栏'),
                onTap: () {
                  Navigator.pop(c);
                  _copyToOther(singlePath: p);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFF85149)),
              title: const Text('删除', style: TextStyle(color: Color(0xFFF85149))),
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

  String _fmtSize(dynamic s) {
    final n = s is int ? s : int.tryParse('$s') ?? 0;
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} K';
    if (n < 1024 * 1024 * 1024) return '${(n / (1024 * 1024)).toStringAsFixed(1)} M';
    return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(1)} G';
  }

  Widget _pane(BuildContext context, _Pane pane, int idx) {
    final focused = focus == idx;
    final border = focused ? const Color(0xFF4FC3F7) : const Color(0xFF333333);
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => focus = idx),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            border: Border.all(color: border, width: focused ? 1.5 : 0.5),
          ),
          child: Column(
            children: [
              Material(
                color: focused ? const Color(0xFF1A2A33) : const Color(0xFF1E1E1E),
                child: Column(
                  children: [
                    // MT-style path strip: ~ / full/path   [↑] [↻]
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 2, 4),
                      child: Row(
                        children: [
                          Text(
                            idx == 0 ? '左' : '右',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: focused ? const Color(0xFF4FC3F7) : const Color(0xFF666666),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('~', style: TextStyle(fontSize: 13, color: Color(0xFF9E9E9E), fontFamily: 'monospace')),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              pane.path.isEmpty ? '/' : pane.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: focused ? Colors.white : const Color(0xFFBDBDBD),
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
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
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                      child: Row(
                        children: [
                          for (final b in const ['', '/etc', '/var/log', '/tmp', '/home', '/root'])
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: ActionChip(
                                visualDensity: VisualDensity.compact,
                                label: Text(b.isEmpty ? '~' : b, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                                onPressed: () {
                                  setState(() => focus = idx);
                                  _go(pane, b);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (pane.err != null)
                Material(
                  color: const Color(0xFF3D1F1F),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(pane.err!, style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11)),
                  ),
                ),
              Expanded(
                child: pane.loading
                    ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                    : pane.entries.isEmpty
                        ? const Center(child: Text('空', style: TextStyle(color: Colors.white38)))
                        : ListView.builder(
                            itemCount: pane.entries.length,
                            itemBuilder: (_, i) {
                              final e = pane.entries[i] as Map;
                              final isDir = e['isDir'] == true;
                              final name = e['name']?.toString() ?? '';
                              final fp = e['path']?.toString() ?? name;
                              final sel = pane.selected.contains(fp);
                              final mtime = e['modTime']?.toString() ?? e['mtime']?.toString() ?? e['time']?.toString() ?? '';
                              final sizeStr = isDir ? '' : _fmtSize(e['size']);
                              return InkWell(
                                onTap: () {
                                  setState(() => focus = idx);
                                  if (pane.selecting) {
                                    setState(() {
                                      if (sel) {
                                        pane.selected.remove(fp);
                                      } else {
                                        pane.selected.add(fp);
                                      }
                                      pane.selecting = pane.selected.isNotEmpty;
                                    });
                                    return;
                                  }
                                  if (isDir) {
                                    _go(pane, fp);
                                  } else {
                                    _openFile(fp);
                                  }
                                },
                                onLongPress: () {
                                  setState(() {
                                    focus = idx;
                                    pane.selecting = true;
                                    pane.selected.add(fp);
                                  });
                                },
                                child: Container(
                                  color: sel ? const Color(0xFF1A3A5C) : Colors.transparent,
                                  padding: const EdgeInsets.fromLTRB(8, 7, 4, 7),
                                  child: Row(
                                    children: [
                                      if (pane.selecting)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: Icon(
                                            sel ? Icons.check_circle : Icons.radio_button_unchecked,
                                            size: 18,
                                            color: sel ? const Color(0xFF4FC3F7) : Colors.white38,
                                          ),
                                        )
                                      else
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8),
                                          child: Icon(
                                            isDir ? Icons.folder : Icons.insert_drive_file_outlined,
                                            size: 22,
                                            color: isDir ? const Color(0xFFFFB74D) : const Color(0xFF90CAF9),
                                          ),
                                        ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                            ),
                                            if (mtime.isNotEmpty || (!isDir && sizeStr.isNotEmpty))
                                              Text(
                                                [
                                                  if (!isDir && sizeStr.isNotEmpty) sizeStr,
                                                  if (mtime.isNotEmpty) mtime,
                                                  if (isDir) (e['mode']?.toString() ?? ''),
                                                ].where((s) => s.toString().isNotEmpty).join('  ·  '),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E), fontFamily: 'monospace'),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (!isDir && sizeStr.isNotEmpty && mtime.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 4),
                                          child: Text(sizeStr, style: const TextStyle(fontSize: 11, color: Color(0xFFBDBDBD), fontFamily: 'monospace')),
                                        ),
                                      if (!pane.selecting)
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                          icon: const Icon(Icons.more_horiz, size: 18, color: Colors.white54),
                                          onPressed: () {
                                            setState(() => focus = idx);
                                            _itemSheet(e);
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    if (state.selectedHostId == null) {
      return const Scaffold(body: Center(child: Text('先选主机')));
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          active.selecting ? '已选 ${active.selected.length}' : (dualPane ? '文件 L | R' : '文件'),
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: dualPane ? '单栏' : '双栏',
            onPressed: () => setState(() => dualPane = !dualPane),
            icon: Icon(dualPane ? Icons.view_agenda_outlined : Icons.view_column_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (a) {
              if (a == 'mkdir') _mkdir();
              if (a == 'newfile') _newFile();
              if (a == 'select') {
                setState(() {
                  active.selecting = true;
                });
              }
              if (a == 'swap') {
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
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'mkdir', child: Text('新建文件夹')),
              PopupMenuItem(value: 'newfile', child: Text('新建文件')),
              PopupMenuItem(value: 'select', child: Text('多选')),
              PopupMenuItem(value: 'swap', child: Text('交换左右路径')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: dualPane
                ? Row(
                    children: [
                      _pane(context, _left, 0),
                      Container(width: 1, color: const Color(0xFF2A2A2A)),
                      _pane(context, _right, 1),
                    ],
                  )
                : Row(children: [_pane(context, active, focus)]),
          ),
          // MT-like bottom bar operates on focused pane / cross-pane
          Material(
            color: const Color(0xFF1E1E1E),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: active.selecting
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _bar(Icons.copy_all, '复制', active.selected.isEmpty ? null : () => _copyToOther()),
                          _bar(Icons.drive_file_move_outline, '移动', active.selected.isEmpty ? null : _moveToOther),
                          _bar(Icons.delete_outline, '删除', active.selected.isEmpty ? null : () => _deletePaths(active.selected, ask: true)),
                          _bar(Icons.close, '取消', () {
                            setState(() {
                              active.selecting = false;
                              active.selected.clear();
                            });
                          }),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _bar(Icons.create_new_folder_outlined, '新建', () async {
                            final a = await showModalBottomSheet<String>(
                              context: context,
                              backgroundColor: const Color(0xFF1E1E1E),
                              builder: (c) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(leading: const Icon(Icons.create_new_folder_outlined), title: const Text('新建文件夹'), onTap: () => Navigator.pop(c, 'dir')),
                                    ListTile(leading: const Icon(Icons.note_add_outlined), title: const Text('新建文件'), onTap: () => Navigator.pop(c, 'file')),
                                  ],
                                ),
                              ),
                            );
                            if (a == 'dir') await _mkdir();
                            if (a == 'file') await _newFile();
                          }),
                          _bar(Icons.checklist, '多选', () => setState(() => active.selecting = true)),
                          _bar(Icons.view_column_outlined, dualPane ? '单栏' : '双栏', () => setState(() => dualPane = !dualPane)),
                          _bar(Icons.swap_horiz, '切栏', () => setState(() => focus = 1 - focus)),
                          _bar(Icons.more_horiz, '更多', () async {
                            final a = await showModalBottomSheet<String>(
                              context: context,
                              backgroundColor: const Color(0xFF1E1E1E),
                              builder: (c) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(leading: const Icon(Icons.refresh), title: const Text('刷新'), onTap: () => Navigator.pop(c, 'refresh')),
                                    ListTile(leading: const Icon(Icons.swap_vert), title: const Text('交换左右路径'), onTap: () => Navigator.pop(c, 'swap')),
                                    ListTile(leading: const Icon(Icons.home_outlined), title: const Text('回到 /'), onTap: () => Navigator.pop(c, 'root')),
                                  ],
                                ),
                              ),
                            );
                            if (a == 'refresh') _load(active);
                            if (a == 'root') _go(active, '/');
                            if (a == 'swap') {
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
                          }),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(IconData icon, String label, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: onTap == null ? Colors.white24 : Colors.white70),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: onTap == null ? Colors.white24 : Colors.white70)),
          ],
        ),
      ),
    );
  }
}
