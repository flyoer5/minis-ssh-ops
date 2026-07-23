import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> with AutomaticKeepAliveClientMixin {
  String filter = 'all';
  String hostFilter = 'all';

  @override
  bool get wantKeepAlive => true;

  String _fmtLocal(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final dt0 = DateTime.tryParse(s);
    if (dt0 == null) return s;
    final dt = dt0.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  Color _riskColor(String risk) {
    switch (risk) {
      case 'destructive':
        return const Color(0xFFF85149);
      case 'write':
        return const Color(0xFFD29922);
      case 'blocked':
        return const Color(0xFFA371F7);
      case 'read':
        return const Color(0xFF3FB950);
      default:
        return const Color(0xFF8B949E);
    }
  }

  String _hostLabel(AppState state, String hostId) {
    if (hostId.isEmpty) return '未知主机';
    for (final raw in state.hosts) {
      if (raw is Map && raw['id']?.toString() == hostId) {
        final name = raw['name']?.toString() ?? '';
        if (name.isNotEmpty) return name;
        return '${raw['host']}:${raw['port']}';
      }
    }
    return hostId.length > 8 ? '${hostId.substring(0, 8)}…' : hostId;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().refreshAudit().catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    final fs = state.recordsFontSize;
    final all = state.audit.whereType<Map>().toList();

    final hostIds = <String>{};
    for (final e in all) {
      final id = e['hostId']?.toString() ?? '';
      if (id.isNotEmpty) hostIds.add(id);
    }

    var list = all;
    if (filter != 'all') {
      list = list.where((e) => (e['risk']?.toString() ?? '') == filter).toList();
    }
    if (hostFilter != 'all') {
      list = list.where((e) => (e['hostId']?.toString() ?? '') == hostFilter).toList();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        toolbarHeight: 44,
        titleSpacing: 12,
        backgroundColor: const Color(0xFF0D1117),
        title: Text('记录', style: TextStyle(fontSize: fs + 1, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '刷新',
            onPressed: () => state.refreshAudit(),
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
            child: Row(
              children: [
                for (final f in const [
                  ['all', '全部'],
                  ['read', '读'],
                  ['write', '写'],
                  ['destructive', '破坏'],
                  ['blocked', '拦截'],
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                      label: Text(f[1], style: TextStyle(fontSize: fs - 1.5)),
                      selected: filter == f[0],
                      onSelected: (_) => setState(() => filter = f[0]),
                    ),
                  ),
              ],
            ),
          ),
          if (hostIds.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                      label: Text('全部主机', style: TextStyle(fontSize: fs - 1.5)),
                      selected: hostFilter == 'all',
                      onSelected: (_) => setState(() => hostFilter = 'all'),
                    ),
                  ),
                  for (final id in hostIds)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                        label: Text(_hostLabel(state, id), style: TextStyle(fontSize: fs - 1.5)),
                        selected: hostFilter == id,
                        onSelected: (_) => setState(() => hostFilter = id),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                list.isEmpty ? '暂无记录' : '共 ${list.length} 条',
                style: TextStyle(fontSize: fs - 2, color: const Color(0xFF8B949E)),
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text('暂无审计记录', style: TextStyle(fontSize: fs, color: const Color(0xFF8B949E))))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF21262D)),
                    itemBuilder: (ctx, i) {
                      final e = list[i];
                      final risk = e['risk']?.toString() ?? '';
                      final cmd = e['command']?.toString() ?? '';
                      final exit = e['exitCode'];
                      final at = _fmtLocal(e['createdAt']?.toString() ?? '');
                      final hostId = e['hostId']?.toString() ?? '';
                      final hostName = _hostLabel(state, hostId);
                      final rc = _riskColor(risk);
                      return InkWell(
                        onTap: () => _showDetail(context, e, hostName, fs),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 3),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(color: rc, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      cmd,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: fs,
                                        fontFamily: 'monospace',
                                        height: 1.3,
                                        color: const Color(0xFFE6EDF3),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 2,
                                      children: [
                                        Text(risk.isEmpty ? '—' : risk, style: TextStyle(fontSize: fs - 2, color: rc, fontWeight: FontWeight.w600)),
                                        Text('exit $exit', style: TextStyle(fontSize: fs - 2, color: const Color(0xFF8B949E), fontFamily: 'monospace')),
                                        Text(hostName, style: TextStyle(fontSize: fs - 2, color: const Color(0xFF79C0FF))),
                                        if (at.isNotEmpty)
                                          Text(at, style: TextStyle(fontSize: fs - 2, color: const Color(0xFF8B949E), fontFamily: 'monospace')),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, size: 16, color: Color(0xFF484F58)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, Map e, String hostName, double fs) {
    final risk = e['risk']?.toString() ?? '';
    final cmd = e['command']?.toString() ?? '';
    final stdout = e['stdout']?.toString() ?? '';
    final stderr = e['stderr']?.toString() ?? '';
    final at = _fmtLocal(e['createdAt']?.toString() ?? '');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        minChildSize: 0.35,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFF30363D), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            Text('命令详情', style: TextStyle(fontSize: fs + 1, fontWeight: FontWeight.w700, color: const Color(0xFFE6EDF3))),
            const SizedBox(height: 8),
            SelectableText(cmd, style: TextStyle(fontFamily: 'monospace', fontSize: fs - 1, color: const Color(0xFFC9D1D9))),
            const SizedBox(height: 10),
            Text('风险 $risk · exit ${e['exitCode']} · $hostName', style: TextStyle(fontSize: fs - 2, color: const Color(0xFF8B949E))),
            if (at.isNotEmpty) Text(at, style: TextStyle(fontSize: fs - 2, color: const Color(0xFF8B949E), fontFamily: 'monospace')),
            if (stdout.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('stdout', style: TextStyle(fontSize: fs - 2, fontWeight: FontWeight.w700, color: const Color(0xFF3FB950))),
              const SizedBox(height: 4),
              SelectableText(stdout, style: TextStyle(fontFamily: 'monospace', fontSize: fs - 2, color: const Color(0xFFC9D1D9))),
            ],
            if (stderr.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('stderr', style: TextStyle(fontSize: fs - 2, fontWeight: FontWeight.w700, color: const Color(0xFFF85149))),
              const SizedBox(height: 4),
              SelectableText(stderr, style: TextStyle(fontFamily: 'monospace', fontSize: fs - 2, color: const Color(0xFFFFB4A9))),
            ],
          ],
        ),
      ),
    );
  }
}
