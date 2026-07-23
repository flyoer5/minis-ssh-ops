import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

/// Host status cards (probe metrics). State kept in page + IndexedStack.
class HostsPage extends StatefulWidget {
  const HostsPage({super.key});

  @override
  State<HostsPage> createState() => _HostsPageState();
}

class _HostsPageState extends State<HostsPage> with AutomaticKeepAliveClientMixin {
  final Map<String, ProbeSummary?> _summary = {};
  final Set<String> _loading = {};
  bool _autoStarted = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    if (!_autoStarted && state.backendOk && state.hosts.isNotEmpty) {
      _autoStarted = true;
      for (final h in state.hosts) {
        if (h is Map && h['id'] is String) {
          unawaited(_refreshProbe(state, h['id'] as String));
        }
      }
    }
  }

  Future<void> _refreshProbe(AppState state, String id, {bool force = false}) async {
    if (_loading.contains(id)) return;
    if (!force) {
      final c = state.getProbeCache(id);
      if (c != null) {
        setState(() => _summary[id] = c);
        return;
      }
    }
    setState(() => _loading.add(id));
    try {
      final s = await state.runProbeSummary(id, force);
      if (mounted) setState(() => _summary[id] = s);
    } catch (_) {
      if (mounted) {
        setState(() {
          _summary[id] = ProbeSummary(
            ok: false,
            oneLine: '离线',
            lines: [ProbeLine('状态', '探测失败')],
            detail: '',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _loading.remove(id));
    }
  }

  Future<void> _refreshAll(AppState state) async {
    await state.refreshHosts();
    await Future.wait([
      for (final h in state.hosts)
        if (h is Map && h['id'] is String) _refreshProbe(state, h['id'] as String),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        titleSpacing: 12,
        title: const Text('主机', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: state.backendOk ? () => _refreshAll(state) : null,
            icon: const Icon(Icons.refresh, size: 20),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: state.backendOk ? () => _showAdd(context, state) : null,
            icon: const Icon(Icons.add, size: 22),
          ),
        ],
      ),
      body: !state.backendOk
          ? Center(child: FilledButton(onPressed: () => state.bootstrap(), child: const Text('连接后端')))
          : state.hosts.isEmpty
              ? const Center(child: Text('无主机'))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                      child: TextField(
                        controller: _search,
                        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: '搜索名称 / 地址 / 用户',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _search.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF1E293B)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF1E293B)),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final q = _query;
                          final list = state.hosts.where((raw) {
                            if (q.isEmpty) return true;
                            final h = raw as Map<String, dynamic>;
                            final name = (h['name']?.toString() ?? '').toLowerCase();
                            final host = (h['host']?.toString() ?? '').toLowerCase();
                            final user = (h['username']?.toString() ?? '').toLowerCase();
                            final note = (h['note']?.toString() ?? h['remark']?.toString() ?? '').toLowerCase();
                            final addr = '$user@$host:${h['port']}';
                            return name.contains(q) ||
                                host.contains(q) ||
                                user.contains(q) ||
                                note.contains(q) ||
                                addr.contains(q);
                          }).toList();
                          if (list.isEmpty) {
                            return const Center(child: Text('无匹配主机', style: TextStyle(color: Color(0xFF64748B))));
                          }
                          return RefreshIndicator(
                            onRefresh: () => _refreshAll(state),
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
                              itemCount: list.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final h = list[i] as Map<String, dynamic>;
                                final id = h['id'] as String;
                                final name = (h['name'] as String?)?.isNotEmpty == true
                                    ? h['name'] as String
                                    : '${h['host']}';
                                final addr = '${h['username']}@${h['host']}:${h['port']}';
                                return _StatusCard(
                                  name: name,
                                  addr: addr,
                                  selected: state.selectedHostId == id,
                                  loading: _loading.contains(id),
                                  summary: _summary[id],
                                  probedAt: state.probeCacheTime(id),
                                  onSelect: () => state.selectHost(id),
                                  onRefresh: () => _refreshProbe(state, id, force: true),
                                  onMenu: () => _hostMenu(context, state, h),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Future<void> _hostMenu(BuildContext context, AppState state, Map<String, dynamic> h) async {
    final id = h['id'] as String;
    final name = (h['name'] as String?)?.isNotEmpty == true ? h['name'] as String : '${h['host']}';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () => Navigator.pop(c, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFF85149)),
              title: const Text('删除', style: TextStyle(color: Color(0xFFF85149))),
              onTap: () => Navigator.pop(c, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'edit') {
      await _showEdit(context, state, h);
      return;
    }
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('删除 $name？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
          ],
        ),
      );
      if (ok == true) {
        await state.removeHost(id);
        setState(() => _summary.remove(id));
      }
    }
  }

  Future<void> _showEdit(BuildContext context, AppState state, Map<String, dynamic> h) async {
    final id = h['id'] as String;
    final name = TextEditingController(text: (h['name'] as String?) ?? '');
    final host = TextEditingController(text: (h['host'] as String?) ?? '');
    final port = TextEditingController(text: '${h['port'] ?? 22}');
    final user = TextEditingController(text: (h['username'] as String?) ?? 'root');
    final password = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('编辑主机'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: name, decoration: const InputDecoration(labelText: '名称')),
                TextFormField(
                  controller: host,
                  decoration: const InputDecoration(labelText: '地址'),
                  validator: (v) => v == null || v.isEmpty ? '必填' : null,
                ),
                TextFormField(
                  controller: port,
                  decoration: const InputDecoration(labelText: '端口'),
                  keyboardType: TextInputType.number,
                ),
                TextFormField(controller: user, decoration: const InputDecoration(labelText: '用户')),
                TextFormField(
                  controller: password,
                  decoration: const InputDecoration(labelText: '密码（留空不改）'),
                  obscureText: true,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (form.currentState?.validate() != true) return;
              Navigator.pop(c, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final body = <String, dynamic>{
      'name': name.text.trim(),
      'host': host.text.trim(),
      'port': int.tryParse(port.text.trim()) ?? 22,
      'username': user.text.trim(),
      if (password.text.isNotEmpty) 'password': password.text,
    };
    try {
      await state.updateHost(id, body);
      await _refreshProbe(state, id, force: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showAdd(BuildContext context, AppState state) async {
    final name = TextEditingController();
    final host = TextEditingController();
    final port = TextEditingController(text: '22');
    final user = TextEditingController(text: 'root');
    final password = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('添加主机'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: name, decoration: const InputDecoration(labelText: '名称')),
              TextFormField(
                controller: host,
                decoration: const InputDecoration(labelText: '地址'),
                validator: (v) => v == null || v.isEmpty ? '必填' : null,
              ),
              TextFormField(controller: port, decoration: const InputDecoration(labelText: '端口'), keyboardType: TextInputType.number),
              TextFormField(controller: user, decoration: const InputDecoration(labelText: '用户')),
              TextFormField(controller: password, decoration: const InputDecoration(labelText: '密码'), obscureText: true),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (form.currentState?.validate() != true) return;
              Navigator.pop(c, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final body = <String, dynamic>{
      'name': name.text.trim(),
      'host': host.text.trim(),
      'port': int.tryParse(port.text.trim()) ?? 22,
      'username': user.text.trim(),
      if (password.text.isNotEmpty) 'password': password.text,
    };
    try {
      await state.addHost(body);
      String? id;
      for (final h in state.hosts) {
        if (h is Map && h['id'] is String) id = h['id'] as String;
      }
      if (id != null) await _refreshProbe(state, id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

class _StatusCard extends StatelessWidget {
  final String name;
  final String addr;
  final bool selected;
  final bool loading;
  final ProbeSummary? summary;
  final DateTime? probedAt;
  final VoidCallback onSelect;
  final VoidCallback onRefresh;
  final VoidCallback onMenu;

  const _StatusCard({
    required this.name,
    required this.addr,
    required this.selected,
    required this.loading,
    required this.summary,
    this.probedAt,
    required this.onSelect,
    required this.onRefresh,
    required this.onMenu,
  });

  String get _ageText {
    final at = probedAt;
    if (at == null || summary == null) return '';
    final sec = DateTime.now().difference(at).inSeconds;
    if (sec < 5) return '刚刚';
    if (sec < 60) return '${sec}s 前';
    final min = sec ~/ 60;
    if (min < 60) return '${min}m 前';
    final h = min ~/ 60;
    if (h < 48) return '${h}h 前';
    return '${h ~/ 24}d 前';
  }

  String _v(String label) {
    if (summary == null) return '—';
    for (final l in summary!.lines) {
      if (l.label == label) {
        final t = l.value.trim();
        return (t.isEmpty || t == '-') ? '—' : t;
      }
    }
    return '—';
  }

  double? _pct(String s) {
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(s);
    if (m != null) return (double.tryParse(m.group(1)!) ?? 0).clamp(0, 100) / 100.0;
    // used/total like 1.2Gi/3.7Gi
    final parts = s.split('/');
    if (parts.length == 2) {
      double? parse(String x) {
        x = x.trim().toUpperCase();
        final m2 = RegExp(r'([\d.]+)\s*([KMGT]?I?B?)').firstMatch(x);
        if (m2 == null) return null;
        var n = double.tryParse(m2.group(1)!) ?? 0;
        final u = m2.group(2) ?? '';
        if (u.startsWith('T')) n *= 1024 * 1024;
        else if (u.startsWith('G')) n *= 1024;
        else if (u.startsWith('M')) n *= 1;
        else if (u.startsWith('K')) n /= 1024;
        return n;
      }
      final a = parse(parts[0]);
      final b = parse(parts[1]);
      if (a != null && b != null && b > 0) return (a / b).clamp(0.0, 1.0);
    }
    return null;
  }

  Color _barColor(double? p) {
    if (p == null) return const Color(0xFF64748B);
    if (p >= 0.9) return const Color(0xFFEF4444);
    if (p >= 0.75) return const Color(0xFFF59E0B);
    return const Color(0xFF22C55E);
  }

  Color get _status {
    if (loading) return const Color(0xFFFBBF24);
    if (summary == null) return const Color(0xFF64748B);
    if (!summary!.ok) return const Color(0xFFEF4444);
    return const Color(0xFF22C55E);
  }

  String get _statusText {
    if (loading) return '探测中';
    if (summary == null) return '未探测';
    return summary!.ok ? 'Online' : 'Offline';
  }

  @override
  Widget build(BuildContext context) {
    // CPU% + MEM + HDD
    final cpuPctS = _v('CPU%');
    final cpuFull = _v('CPU');
    final diskPctS = _v('磁盘%');
    final diskFull = _v('磁盘');
    final memMain = _v('内存主');
    final memFull = _v('内存');
    final up = _v('运行');
    final sys = _v('系统');

    final diskP = _pct(diskPctS) ?? _pct(diskFull);
    final memP = _pct(memMain) ?? _pct(memFull);
    final cpuP = _pct(cpuPctS) ?? _pct(cpuFull);

    return Material(
      color: const Color(0xFF0F1419),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? const Color(0xFF3B82F6) : const Color(0xFF1E293B),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSelect,
        onLongPress: onMenu,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // compact header: dot · name · status · actions
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: _status, shape: BoxShape.circle, boxShadow: [
                      BoxShadow(color: _status.withAlpha(0x66), blurRadius: 6),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
                    ),
                  ),
                  Text(
                    _statusText,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _status),
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.only(left: 8, right: 6),
                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else ...[
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: onRefresh,
                      icon: const Icon(Icons.sync, size: 16, color: Color(0xFF64748B)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: onMenu,
                      icon: const Icon(Icons.more_vert, size: 16, color: Color(0xFF64748B)),
                    ),
                  ],
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 1),
                child: Text(addr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontFamily: 'monospace')),
              ),
              const SizedBox(height: 6),
              if (summary == null && !loading)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text('下拉或点同步获取探针数据', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                )
              else ...[
                // ServerStatus style: label | value (no duplicate %) | bar
                // CPU utilization % (sampled /proc/stat)
                _metricRow(
                  'CPU',
                  cpuPctS == '—' ? cpuFull : cpuPctS,
                  cpuP,
                  const Color(0xFF38BDF8),
                ),
                const SizedBox(height: 5),
                // MEM: prefer "used/total" only; % comes from bar + optional once
                _metricRow(
                  'MEM',
                  () {
                    // memFull like "42% (1.2Gi/3.7Gi)" or memMain "42%" / "1.2Gi"
                    final full = memFull;
                    final m = RegExp(r'\(([^)]+)\)').firstMatch(full);
                    if (m != null) return m.group(1)!; // used/total
                    if (memMain.contains('/') ) return memMain;
                    if (full.contains('/')) {
                      final parts = full.split(RegExp(r'\s+'));
                      for (final p in parts) {
                        if (p.contains('/') && !p.contains('%')) return p;
                      }
                    }
                    return memMain == '—' ? full : memMain;
                  }(),
                  memP,
                  const Color(0xFFA78BFA),
                ),
                const SizedBox(height: 5),
                _metricRow(
                  'HDD',
                  () {
                    final full = diskFull;
                    final m = RegExp(r'\(([^)]+)\)').firstMatch(full);
                    if (m != null) return m.group(1)!;
                    if (diskPctS != '—' && full != '—' && full != diskPctS) {
                      // strip leading "51% " if present
                      final cleaned = full.replaceFirst(RegExp(r'^\d+%\s*'), '').replaceAll(RegExp(r'[()]'), '');
                      if (cleaned.contains('/')) return cleaned;
                    }
                    return diskPctS == '—' ? full : diskPctS;
                  }(),
                  diskP,
                  const Color(0xFF34D399),
                ),
                const SizedBox(height: 6),
                // uptime + OS + probe age
                Text(
                  [
                    if (up != '—') '⏱ $up',
                    if (sys != '—') sys,
                    if (_ageText.isNotEmpty) _ageText,
                  ].join('  ·  '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: () {
                      final at = probedAt;
                      if (at == null) return const Color(0xFF94A3B8);
                      final sec = DateTime.now().difference(at).inSeconds;
                      if (sec > 120) return const Color(0xFFF59E0B); // stale
                      return const Color(0xFF94A3B8);
                    }(),
                    fontFamily: 'monospace',
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricRow(String label, String value, double? progress, Color accent, {bool showPct = true}) {
    final c = progress == null ? accent : _barColor(progress);
    // Only append % when value itself has none (avoids "51% 51% (19G/40G) 51%")
    final hasPct = value.contains('%');
    final pctText = (showPct && progress != null && !hasPct)
        ? '  ${(progress * 100).toStringAsFixed(0)}%'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accent, letterSpacing: 0.5)),
            ),
            Expanded(
              child: Text(
                value + pctText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600, color: Color(0xFFE2E8F0)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress?.clamp(0.0, 1.0) ?? 0,
            minHeight: 4,
            backgroundColor: const Color(0xFF1E293B),
            color: progress == null ? const Color(0xFF334155) : c,
          ),
        ),
      ],
    );
  }
}
