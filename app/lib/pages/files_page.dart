import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/backend/native_backend.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

/// File browser closer to MT Manager: path bar, multi-select, bottom actions.
class FilesPage extends StatefulWidget {
  const FilesPage({super.key});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> with AutomaticKeepAliveClientMixin {
  String path = '';
  List<dynamic> entries = [];
  bool loading = false;
  String? err;
  String? hostId;
  bool selecting = false;
  final Set<String> selected = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.watch<AppState>();
    if (s.selectedHostId != null && s.selectedHostId != hostId && s.backendOk) {
      hostId = s.selectedHostId;
      _load();
    }
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    setState(() {
      loading = true;
      err = null;
      selected.clear();
      selecting = false;
    });
    try {
      final r = await s.api.fsList(id, path);
      final list = List<dynamic>.from((r['entries'] as List?) ?? []);
      list.sort((a, b) {
        final am = a as Map, bm = b as Map;
        final ad = am['isDir'] == true, bd = bm['isDir'] == true;
        if (ad != bd) return ad ? -1 : 1;
        return (am['name']?.toString() ?? '').toLowerCase().compareTo((bm['name']?.toString() ?? '').toLowerCase());
      });
      setState(() {
        entries = list;
        final rp = r['path']?.toString();
        if (rp != null && rp.isNotEmpty) path = rp;
      });
    } catch (e) {
      setState(() => err = '$e');
    } finally {
      setState(() => loading = false);
    }
  }

  void _up() {
    if (path.isEmpty || path == '/') return;
    final p = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final i = p.lastIndexOf('/');
    setState(() => path = i <= 0 ? '/' : p.substring(0, i));
    _load();
  }

  void _toggleSelect(String p) {
    setState(() {
      if (selected.contains(p)) {
        selected.remove(p);
      } else {
        selected.add(p);
      }
      selecting = selected.isNotEmpty;
    });
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
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _mkdir() async {
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
    final full = path.endsWith('/') || path.isEmpty ? '$path$name' : '$path/$name';
    try {
      await s.api.fsMkdir(id, full, confirmed: true);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _newFile() async {
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
              TextField(controller: bodyCtrl, maxLines: 8, decoration: const InputDecoration(labelText: '内容')),
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
    final full = path.endsWith('/') || path.isEmpty ? '$path$name' : '$path/$name';
    try {
      await s.api.fsWrite(id, full, bodyCtrl.text, confirmed: true);
      await _load();
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
      await _load();
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
      final bytes = base64Decode(b64);
      String text = '';
      try {
        text = utf8.decode(bytes, allowMalformed: true);
      } catch (_) {}
      final looksText = text.isNotEmpty && !text.contains('\u0000') && size is int && size < 512 * 1024;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(n),
          content: Text(saved != null ? '已保存 $size 字节\n$saved' : '已拉取 $size 字节'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
            if (looksText || b64.isNotEmpty)
              FilledButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: looksText ? text : b64));
                  if (c.mounted) Navigator.pop(c);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
                  }
                },
                child: Text(looksText ? '复制文本' : '复制 base64'),
              ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteOne(String p, bool isDir) async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(isDir ? '删除文件夹？' : '删除文件？'),
        content: Text(p),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await s.api.fsRemove(id, p, recursive: isDir, confirmed: true);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteSelected() async {
    if (selected.isEmpty) return;
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('删除 ${selected.length} 项？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    for (final p in selected.toList()) {
      final e = entries.cast<Map>().firstWhere((x) => x['path'] == p, orElse: () => {'isDir': false});
      try {
        await s.api.fsRemove(id, p, recursive: e['isDir'] == true, confirmed: true);
      } catch (_) {}
    }
    await _load();
  }

  void _showItemSheet(Map e) {
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
            ListTile(title: Text(name, style: const TextStyle(fontFamily: 'monospace')), subtitle: Text(p, maxLines: 2)),
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
                  setState(() => path = p);
                  _load();
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
              leading: const Icon(Icons.delete_outline, color: Color(0xFFF85149)),
              title: const Text('删除', style: TextStyle(color: Color(0xFFF85149))),
              onTap: () {
                Navigator.pop(c);
                _deleteOne(p, isDir);
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    if (state.selectedHostId == null) {
      return const Scaffold(body: Center(child: Text('先选主机')));
    }
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: selecting ? Text('已选 ${selected.length}') : const Text('文件'),
        leading: selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  selecting = false;
                  selected.clear();
                }),
              )
            : null,
        actions: [
          if (!selecting) ...[
            IconButton(onPressed: _up, icon: const Icon(Icons.arrow_upward)),
            IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh)),
            PopupMenuButton<String>(
              onSelected: (a) {
                if (a == 'mkdir') _mkdir();
                if (a == 'newfile') _newFile();
                if (a == 'select') setState(() => selecting = true);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'mkdir', child: Text('新建文件夹')),
                PopupMenuItem(value: 'newfile', child: Text('新建文件')),
                PopupMenuItem(value: 'select', child: Text('多选')),
              ],
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: () {
                setState(() {
                  selected
                    ..clear()
                    ..addAll(entries.whereType<Map>().map((e) => e['path']?.toString() ?? ''));
                  selected.removeWhere((e) => e.isEmpty);
                });
              },
            ),
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _deleteSelected),
          ],
        ],
      ),
      body: Column(
        children: [
          // path bar like MT
          Material(
            color: const Color(0xFF1E1E1E),
            child: Column(
              children: [
                InkWell(
                  onLongPress: () async {
                    await Clipboard.setData(ClipboardData(text: path.isEmpty ? '/' : path));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('路径已复制')));
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Row(
                      children: [
                        const Icon(Icons.folder, size: 18, color: Color(0xFFFFB74D)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            path.isEmpty ? '/' : path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    children: [
                      for (final b in const ['', '/sdcard', '/data', '/etc', '/var/log', '/tmp', '/home', '/root'])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              b.isEmpty ? '~' : b,
                              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                            ),
                            onPressed: () {
                              setState(() => path = b);
                              _load();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (err != null)
            Material(
              color: const Color(0xFF3D1F1F),
              child: ListTile(
                dense: true,
                title: Text(err!, style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12)),
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: entries.isEmpty
                        ? ListView(children: const [SizedBox(height: 120), Center(child: Text('空目录'))])
                        : ListView.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF2A2A2A)),
                            itemBuilder: (_, i) {
                              final e = entries[i] as Map;
                              final isDir = e['isDir'] == true;
                              final name = e['name']?.toString() ?? '';
                              final fp = e['path']?.toString() ?? name;
                              final sel = selected.contains(fp);
                              return ListTile(
                                dense: true,
                                selected: sel,
                                selectedTileColor: const Color(0xFF1A3A5C),
                                leading: selecting
                                    ? Checkbox(
                                        value: sel,
                                        onChanged: (_) => _toggleSelect(fp),
                                      )
                                    : Icon(
                                        isDir ? Icons.folder : Icons.insert_drive_file,
                                        color: isDir ? const Color(0xFFFFB74D) : const Color(0xFF90CAF9),
                                      ),
                                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  isDir ? (e['mode']?.toString() ?? 'dir') : '${_fmtSize(e['size'])}  ${e['mode'] ?? ''}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E), fontFamily: 'monospace'),
                                ),
                                trailing: selecting
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.more_vert, size: 18),
                                        onPressed: () => _showItemSheet(e),
                                      ),
                                onTap: () {
                                  if (selecting) {
                                    _toggleSelect(fp);
                                    return;
                                  }
                                  if (isDir) {
                                    setState(() => path = fp);
                                    _load();
                                  } else {
                                    _openFile(fp);
                                  }
                                },
                                onLongPress: () {
                                  if (!selecting) {
                                    setState(() {
                                      selecting = true;
                                      selected.add(fp);
                                    });
                                  } else {
                                    _toggleSelect(fp);
                                  }
                                },
                              );
                            },
                          ),
                  ),
          ),
          // bottom action bar like MT
          if (!selecting)
            Material(
              color: const Color(0xFF1E1E1E),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _barBtn(Icons.create_new_folder_outlined, '新建夹', _mkdir),
                      _barBtn(Icons.note_add_outlined, '新文件', _newFile),
                      _barBtn(Icons.checklist, '多选', () => setState(() => selecting = true)),
                      _barBtn(Icons.refresh, '刷新', loading ? null : _load),
                    ],
                  ),
                ),
              ),
            )
          else
            Material(
              color: const Color(0xFF1E1E1E),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _barBtn(Icons.delete_outline, '删除', selected.isEmpty ? null : _deleteSelected),
                      _barBtn(Icons.close, '取消', () => setState(() {
                            selecting = false;
                            selected.clear();
                          })),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _barBtn(IconData icon, String label, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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

  String _fmtSize(dynamic s) {
    final n = s is int ? s : int.tryParse('$s') ?? 0;
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} K';
    if (n < 1024 * 1024 * 1024) return '${(n / (1024 * 1024)).toStringAsFixed(1)} M';
    return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(1)} G';
  }
}
