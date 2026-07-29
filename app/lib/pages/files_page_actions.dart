part of 'files_page.dart';

extension _FilesPageActionHelpers on _FilesPageState {
  Future<void> _editPath(_Pane pane) async {
    final ctrl = TextEditingController(text: pane.path.isEmpty ? '/' : pane.path);
    final next = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Open path'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          decoration: const InputDecoration(
            hintText: '/var/log',
            helperText: 'Enter an absolute path or a path relative to root.',
          ),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Open')),
        ],
      ),
    );
    if (next == null) return;
    var p = next.trim();
    if (p.isEmpty) p = '/';
    if (!p.startsWith('/')) p = '/$p';
    while (p.contains('//')) {
      p = p.replaceAll('//', '/');
    }
    _go(pane, p);
  }

  void _sortEntries(List<dynamic> list) {
    int cmp(dynamic a, dynamic b) {
      final am = a as Map, bm = b as Map;
      final ad = am['isDir'] == true, bd = bm['isDir'] == true;
      if (ad != bd) return ad ? -1 : 1;
      int c = 0;
      switch (sortBy) {
        case 'size':
          final asz = (am['size'] as num?)?.toInt() ?? 0;
          final bsz = (bm['size'] as num?)?.toInt() ?? 0;
          c = asz.compareTo(bsz);
          break;
        case 'mtime':
          final at = am['modTime']?.toString() ?? am['mtime']?.toString() ?? am['time']?.toString() ?? '';
          final bt = bm['modTime']?.toString() ?? bm['mtime']?.toString() ?? bm['time']?.toString() ?? '';
          c = at.compareTo(bt);
          break;
        case 'name':
        default:
          c = (am['name']?.toString() ?? '').toLowerCase().compareTo((bm['name']?.toString() ?? '').toLowerCase());
      }
      if (c == 0) {
        c = (am['name']?.toString() ?? '').toLowerCase().compareTo((bm['name']?.toString() ?? '').toLowerCase());
      }
      return sortAsc ? c : -c;
    }

    list.sort(cmp);
  }

  void _resortOpenPanes() {
    setState(() {
      _sortEntries(_left.entries);
      _sortEntries(_right.entries);
    });
  }

  Future<void> _pickSort() async {
    final a = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.darkBar,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(sortBy == 'name' ? Icons.check : null, size: 18),
              title: const Text('Name'),
              onTap: () => Navigator.pop(c, 'name'),
            ),
            ListTile(
              leading: Icon(sortBy == 'size' ? Icons.check : null, size: 18),
              title: const Text('Size'),
              onTap: () => Navigator.pop(c, 'size'),
            ),
            ListTile(
              leading: Icon(sortBy == 'mtime' ? Icons.check : null, size: 18),
              title: const Text('Time'),
              onTap: () => Navigator.pop(c, 'mtime'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 18),
              title: Text(sortAsc ? 'Ascending' : 'Descending'),
              onTap: () => Navigator.pop(c, 'toggle'),
            ),
          ],
        ),
      ),
    );
    if (a == null) return;
    setState(() {
      if (a == 'toggle') {
        sortAsc = !sortAsc;
      } else if (sortBy == a) {
        sortAsc = !sortAsc;
      } else {
        sortBy = a;
        sortAsc = true;
      }
    });
    _resortOpenPanes();
  }

  Future<void> _openFile(String p) async {
    final s = context.read<AppState>();
    final id = s.selectedHostId;
    if (id == null) return;
    try {
      final r = await s.api.fsRead(id, p);
      if (!mounted) return;
      if (r['tooLarge'] == true) {
        final go = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('File too large'),
            content: Text('${r['error'] ?? 'This file is too large to preview.'}\nForce open anyway?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Open')),
            ],
          ),
        );
        if (go != true || !mounted) return;
        final r2 = await s.api.fsRead(id, p, force: true);
        if (!mounted) return;
        await _pushEditor(id, p, r2['text']?.toString() ?? '');
        return;
      }
      if (r['binary'] == true) {
        final go = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Binary file'),
            content: const Text('This looks like a binary file. Open it anyway?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Open')),
            ],
          ),
        );
        if (go != true || !mounted) return;
        final r2 = await s.api.fsRead(id, p, force: true);
        if (!mounted) return;
        await _pushEditor(id, p, r2['text']?.toString() ?? '');
        return;
      }
      await _pushEditor(id, p, r['text']?.toString() ?? '');
    } catch (e) {
      if (mounted) showSnack(context, cleanError(e));
    }
  }

  Future<void> _pushEditor(String hostId, String path, String text) async {
    final s = context.read<AppState>();
    Map? meta;
    for (final e in active.entries) {
      if (e is Map && e['path']?.toString() == path) {
        meta = e;
        break;
      }
    }
    final size = (meta?['size'] as num?)?.toInt();
    final mode = meta?['mode']?.toString() ?? meta?['perm']?.toString();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FileEditorPage(
          path: path,
          initialText: text,
          remoteSize: size,
          remoteMode: mode,
          onSave: (body) async {
            await s.api.fsWrite(hostId, path, body, confirmed: true);
            if (mounted) await _load(active);
          },
        ),
      ),
    );
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
        title: const Text('Create folder'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'new-folder')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Create')),
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
      if (mounted) showSnack(context, cleanError(e));
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
        title: const Text('Create file'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Filename')),
              TextField(controller: bodyCtrl, maxLines: 6, decoration: const InputDecoration(labelText: 'Content')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Create')),
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
      if (mounted) showSnack(context, cleanError(e));
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
        title: const Text('Rename'),
        content: TextField(controller: ctrl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Save')),
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
      if (mounted) showSnack(context, cleanError(e));
    }
  }
}
