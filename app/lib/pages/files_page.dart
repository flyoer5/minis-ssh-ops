import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/backend/native_backend.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

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
    });
    try {
      final r = await s.api.fsList(id, path);
      setState(() {
        entries = (r['entries'] as List?) ?? [];
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
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
        title: const Text('新建目录'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: '目录名')),
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

  Future<void> _uploadText() async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    final nameCtrl = TextEditingController(text: 'note.txt');
    final bodyCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('上传文本文件'),
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
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('上传')),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已上传')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _delete(String p, bool isDir) async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(isDir ? '删除目录？' : '删除文件？'),
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

  Future<void> _rename(String oldPath, String oldName, bool isDir) async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    final ctrl = TextEditingController(text: oldName);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: '新名称')),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已重命名')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _download(String filePath) async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    try {
      final r = await s.api.fsDownload(id, filePath);
      final name = r['name']?.toString() ?? 'file.bin';
      final b64 = r['b64']?.toString() ?? '';
      final size = r['size'] ?? 0;
      if (!mounted) return;
      final bytes = base64Decode(b64);
      String asText = '';
      try {
        asText = utf8.decode(bytes, allowMalformed: true);
      } catch (_) {}
      final looksText =
          asText.isNotEmpty && !asText.contains('\u0000') && size is int && size < 512 * 1024;

      String? savedPath;
      try {
        savedPath = await NativeBackend.saveBytesToDownloads(name: name, b64: b64);
      } catch (_) {
        savedPath = null;
      }

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(name),
          content: Text(
            savedPath != null
                ? '已保存 $size 字节到下载目录：\n$savedPath'
                : '已拉取 $size 字节（无法写入下载目录时可复制内容）。',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
            if (looksText || b64.isNotEmpty)
              FilledButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: looksText ? asText : b64));
                  if (c.mounted) Navigator.pop(c);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(looksText ? '已复制文本' : '已复制 base64')),
                    );
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    if (state.selectedHostId == null) {
      return const Scaffold(body: Center(child: Text('先选主机')));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件'),
        actions: [
          IconButton(onPressed: _up, icon: const Icon(Icons.arrow_upward)),
          IconButton(onPressed: _mkdir, icon: const Icon(Icons.create_new_folder_outlined)),
          IconButton(onPressed: _uploadText, icon: const Icon(Icons.upload_file)),
          IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: const Color(0xFF161B22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  dense: true,
                  title: Text(
                    path.isEmpty ? '~' : path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  subtitle: Text(state.hostLabel, style: const TextStyle(fontSize: 11)),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
                      for (final b in const ['', '/etc', '/var/log', '/tmp', '/home'])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text(b.isEmpty ? '~' : b, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
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
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(err!, style: const TextStyle(color: Color(0xFFF85149))),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = entries[i] as Map;
                        final isDir = e['isDir'] == true;
                        final name = e['name']?.toString() ?? '';
                        final p = e['path']?.toString() ?? name;
                        return ListTile(
                          leading: Icon(isDir ? Icons.folder : Icons.insert_drive_file_outlined),
                          title: Text(name),
                          subtitle: Text('${e['mode'] ?? ''} · ${e['size'] ?? 0}', style: const TextStyle(fontSize: 11)),
                          trailing: PopupMenuButton<String>(
                            onSelected: (a) async {
                              if (a == 'open') {
                                if (isDir) {
                                  setState(() => path = p);
                                  _load();
                                } else {
                                  await _openFile(p);
                                }
                              } else if (a == 'rename') {
                                await _rename(p, name, isDir);
                              } else if (a == 'download') {
                                await _download(p);
                              } else if (a == 'delete') {
                                await _delete(p, isDir);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'open', child: Text(isDir ? '打开' : '查看/编辑')),
                              const PopupMenuItem(value: 'rename', child: Text('重命名')),
                              if (!isDir) const PopupMenuItem(value: 'download', child: Text('下载到本机')),
                              const PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                          onTap: () {
                            if (isDir) {
                              setState(() => path = p);
                              _load();
                            } else {
                              _openFile(p);
                            }
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
