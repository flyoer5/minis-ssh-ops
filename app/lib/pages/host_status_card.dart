part of 'hosts_page.dart';

class _StatusCard extends StatelessWidget {
  final String name;
  final String addr;
  final bool selected;
  final bool loading;
  final ProbeSummary? summary;
  final DateTime? probedAt;
  final double fontSize;
  final bool compact;
  final String authKind;
  final VoidCallback onSelect;
  final VoidCallback onRefresh;
  final VoidCallback onMenu;
  final VoidCallback? onShowDetail;
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

  @override
  Widget build(BuildContext context) {
    final cpuPctS = _v('CPU%');
    final cpuFull = _v('CPU');
    final diskPctS = _v('Disk%');
    final diskFull = _v('Disk');
    final memMain = _v('Memory%');
    final memFull = _v('Memory');
    final up = _v('Uptime');
    final sys = _v('System');

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
                      tooltip: '详情',
                      onPressed: onShowDetail,
                      icon: const Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
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
                if (!compact) ...[
                  _metricRow('CPU', cpuPctS == '-' ? cpuFull : cpuPctS, cpuP, AppColors.metricBlue),
                  const SizedBox(height: 5),
                ],
                _metricRow(
                  'MEM',
                  () {
                    final full = memFull;
                    final m = RegExp(r'\(([^)]+)\)').firstMatch(full);
                    if (m != null) return m.group(1)!;
                    if (memMain.contains('/')) return memMain;
                    if (full.contains('/')) {
                      final parts = full.split(RegExp(r'\s+'));
                      for (final p in parts) {
                        if (p.contains('/') && !p.contains('%')) return p;
                      }
                    }
                    return memMain == '-' ? full : memMain;
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
                    if (diskPctS != '-' && full != '-' && full != diskPctS) {
                      final cleaned = full.replaceFirst(RegExp(r'^\d+%\s*'), '').replaceAll(RegExp(r'[()]'), '');
                      if (cleaned.contains('/')) return cleaned;
                    }
                    return diskPctS == '-' ? full : diskPctS;
                  }(),
                  diskP,
                  AppColors.metricTeal,
                ),
                if (!compact) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (up != '-') 'Uptime $up',
                      if (sys != '-') sys,
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
                        if (sec > 120) return AppColors.warnAlt;
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

  Widget _metricRow(String label, String value, double? progress, Color accent, {bool showPct = true}) {
    final c = progress == null ? accent : _barColor(progress);
    final hasPct = value.contains('%');
    final pctText = showPct && progress != null && !hasPct ? '  ${(progress * 100).toStringAsFixed(0)}%' : '';
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
