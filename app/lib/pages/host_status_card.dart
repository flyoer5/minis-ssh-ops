part of 'hosts_page.dart';

class _StatusCard extends StatelessWidget {
  final String name;
  final String addr;
  final bool selected;
  final bool loading;
  final ProbeSummary? summary;
  final DateTime? probedAt;
  final double fontSize;

  /// When true, only MEM + HDD rows (no CPU / uptime footer).
  final bool compact;

  /// `password` | `key` | empty
  final String authKind;
  final VoidCallback onSelect;
  final VoidCallback onRefresh;
  final VoidCallback onMenu;
  final VoidCallback? onShowDetail;

  /// When false, long-press is free for reorder drag (menu only via ⋮).
  final bool longPressOpensMenu;

  const _StatusCard({
    required this.name,
    required this.addr,
    required this.selected,
    required this.loading,
    required this.summary,
    this.probedAt,
    this.fontSize = 14,
    this.compact = false,
    this.authKind = '',
    required this.onSelect,
    required this.onRefresh,
    required this.onMenu,
    this.onShowDetail,
    this.longPressOpensMenu = true,
  });

  String get _ageText {
    final at = probedAt;
    if (at == null || summary == null) return '';
    final sec = DateTime.now().difference(at).inSeconds;
    if (sec < 5) return '刚刚';
    if (sec < 60) return '$sec 秒前';
    final min = sec ~/ 60;
    if (min < 60) return '$min 分钟前';
    final h = min ~/ 60;
    if (h < 48) return '$h 小时前';
    return '${h ~/ 24} 天前';
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
    if (m != null) {
      return (double.tryParse(m.group(1)!) ?? 0).clamp(0, 100) / 100.0;
    }
    // used/total like 1.2Gi/3.7Gi
    final parts = s.split('/');
    if (parts.length == 2) {
      double? parse(String x) {
        x = x.trim().toUpperCase();
        final m2 = RegExp(r'([\d.]+)\s*([KMGT]?I?B?)').firstMatch(x);
        if (m2 == null) return null;
        var n = double.tryParse(m2.group(1)!) ?? 0;
        final u = m2.group(2) ?? '';
        if (u.startsWith('T')) {
          n *= 1024 * 1024;
        } else if (u.startsWith('G')) {
          n *= 1024;
        } else if (u.startsWith('K')) {
          n /= 1024;
        }
        return n;
      }

      final a = parse(parts[0]);
      final b = parse(parts[1]);
      if (a != null && b != null && b > 0) {
        return (a / b).clamp(0.0, 1.0);
      }
    }
    return null;
  }

  Color _barColor(double? p) {
    if (p == null) return AppColors.slate;
    if (p >= 0.9) return AppColors.dangerAlt;
    if (p >= 0.75) return AppColors.warnAlt;
    return AppColors.metricGreen;
  }

  Color get _status {
    if (loading) return AppColors.warnBright;
    if (summary == null) return AppColors.slate;
    if (!summary!.ok) return AppColors.dangerAlt;
    return AppColors.metricGreen;
  }

  String get _statusText {
    if (loading) return '探测中';
    if (summary == null) return '未探测';
    if (summary!.ok) return '在线';
    // Never dump raw SSH errors into the status chip; details live in 探针详情.
    final o = summary!.oneLine.trim();
    if (o.isEmpty || o == '—' || o == '离线' || o.toLowerCase() == 'offline') {
      return '离线';
    }
    if (o.startsWith('错误') || o.toLowerCase().contains('ssh') || o.length > 24) {
      return '离线';
    }
    // Short friendly reasons only (e.g. 认证失败)
    return o;
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
      color: AppColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? AppColors.selectBlue2 : AppColors.slateDeep,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSelect,
        onLongPress: longPressOpensMenu ? onMenu : null,
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
                    decoration: BoxDecoration(
                      color: _status,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: _status.withAlpha(0x66), blurRadius: 6),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: fontSize + 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  Text(
                    _statusText,
                    style: TextStyle(
                      fontSize: fontSize - 3,
                      fontWeight: FontWeight.w700,
                      color: _status,
                    ),
                  ),
                  if (onShowDetail != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      tooltip: '探针详情',
                      onPressed: onShowDetail,
                      icon: const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                    ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.only(left: 8, right: 6),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else ...[
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: onRefresh,
                      icon: const Icon(Icons.sync, size: 16, color: AppColors.slate),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: onMenu,
                      icon: const Icon(Icons.more_vert, size: 16, color: AppColors.slate),
                    ),
                  ],
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 1),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        addr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.slate,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    if (authKind == 'key' || authKind == 'password')
                      Padding(
                        padding: const EdgeInsets.only(left: 6, right: 4),
                        child: Icon(
                          authKind == 'key' ? Icons.vpn_key : Icons.password,
                          size: 12,
                          color: AppColors.slateMuted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              if (summary == null && !loading)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text(
                    '下拉或点同步获取探针数据',
                    style: TextStyle(fontSize: 12, color: AppColors.slateMuted),
                  ),
                )
              else ...[
                // ServerStatus style: label | value (no duplicate %) | bar
                if (!compact) ...[
                  // CPU utilization % (sampled /proc/stat)
                  _metricRow(
                    'CPU',
                    cpuPctS == '—' ? cpuFull : cpuPctS,
                    cpuP,
                    AppColors.metricBlue,
                  ),
                  const SizedBox(height: 5),
                ],
                // MEM: prefer "used/total" only; % comes from bar + optional once
                _metricRow(
                  'MEM',
                  () {
                    // memFull like "42% (1.2Gi/3.7Gi)" or memMain "42%" / "1.2Gi"
                    final full = memFull;
                    final m = RegExp(r'\(([^)]+)\)').firstMatch(full);
                    if (m != null) return m.group(1)!; // used/total
                    if (memMain.contains('/')) return memMain;
                    if (full.contains('/')) {
                      final parts = full.split(RegExp(r'\s+'));
                      for (final p in parts) {
                        if (p.contains('/') && !p.contains('%')) return p;
                      }
                    }
                    return memMain == '—' ? full : memMain;
                  }(),
                  memP,
                  AppColors.purple,
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
                      final cleaned = full
                          .replaceFirst(RegExp(r'^\d+%\s*'), '')
                          .replaceAll(RegExp(r'[()]'), '');
                      if (cleaned.contains('/')) return cleaned;
                    }
                    return diskPctS == '—' ? full : diskPctS;
                  }(),
                  diskP,
                  AppColors.metricTeal,
                ),
                if (!compact) ...[
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
                      fontSize: fontSize - 4,
                      color: () {
                        final at = probedAt;
                        if (at == null) return AppColors.slateText;
                        final sec = DateTime.now().difference(at).inSeconds;
                        if (sec > 120) return AppColors.warnAlt; // stale
                        return AppColors.slateText;
                      }(),
                      fontFamily: 'monospace',
                      height: 1.25,
                    ),
                  ),
                ] else if (_ageText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _ageText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fontSize - 4,
                      color: AppColors.slateText,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricRow(
    String label,
    String value,
    double? progress,
    Color accent, {
    bool showPct = true,
  }) {
    final c = progress == null ? accent : _barColor(progress);
    // Only append % when value itself has none (avoids "51% 51% (19G/40G) 51%")
    final hasPct = value.contains('%');
    final pctText = showPct && progress != null && !hasPct
        ? '  ${(progress * 100).toStringAsFixed(0)}%'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: fontSize - 3,
                  fontWeight: FontWeight.w800,
                  color: accent,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value + pctText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: fontSize - 2,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: AppColors.slateLine,
                ),
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
            backgroundColor: AppColors.slateDeep,
            color: progress == null ? AppColors.slateBar : c,
          ),
        ),
      ],
    );
  }
}
