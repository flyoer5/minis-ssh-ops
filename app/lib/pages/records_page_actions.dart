part of 'records_page.dart';

extension RecordsPageActions on _RecordsPageState {
  Future<void> _exportCsv(BuildContext context, AppState state, List<Map> list) async {
    final buf = StringBuffer();
    buf.writeln('createdAt,host,hostId,risk,exitCode,command,stdout,stderr');
    for (final e in list) {
      final hostId = e['hostId']?.toString() ?? '';
      final hostName = _hostLabel(state, hostId);
      final at = _fmtLocal(e['createdAt']?.toString() ?? '');
      final row = [
        at,
        hostName,
        hostId,
        e['risk']?.toString() ?? '',
        '${e['exitCode'] ?? ''}',
        e['command']?.toString() ?? '',
        e['stdout']?.toString() ?? '',
        e['stderr']?.toString() ?? '',
      ].map(_csvEscape).join(',');
      buf.writeln(row);
    }
    final csv = buf.toString();
    String? savedPath;
    if (NativeBackend.isAndroidNative) {
      try {
        final name =
            'jishu-audit-${DateTime.now().toIso8601String().replaceAll(':', '').replaceAll('.', '').substring(0, 15)}.csv';
        final b64 = base64Encode(utf8.encode(csv));
        savedPath = await NativeBackend.saveBytesToDownloads(name: name, b64: b64);
      } catch (_) {
        savedPath = null;
      }
    }
    await Clipboard.setData(ClipboardData(text: csv));
    if (!context.mounted) return;
    var shared = false;
    if (NativeBackend.isAndroidNative) {
      try {
        final name =
            'jishu-audit-${DateTime.now().toIso8601String().replaceAll(':', '').replaceAll('.', '').substring(0, 15)}.csv';
        final b64 = base64Encode(utf8.encode(csv));
        await NativeBackend.shareFile(
          name: name,
          b64: b64,
          mime: 'text/csv',
          title: '导出审计记录 (${list.length})',
        );
        shared = true;
      } catch (_) {
        try {
          await NativeBackend.shareText(text: csv, title: '审计 CSV (${list.length})');
          shared = true;
        } catch (_) {
          shared = false;
        }
      }
    }
    if (!context.mounted) return;
    final msg = shared
        ? '已打开系统分享（${list.length} 条），并复制到剪贴板'
        : (savedPath != null && savedPath.isNotEmpty
            ? '已导出 ${list.length} 条到下载目录，并复制到剪贴板'
            : '已复制 ${list.length} 条 CSV 到剪贴板');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        action: SnackBarAction(
          label: '预览',
          onPressed: () {
            showDialog(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('CSV 预览'),
                content: SizedBox(
                  width: double.maxFinite,
                  height: 320,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      savedPath != null && savedPath.isNotEmpty ? '文件: $savedPath\n\n$csv' : csv,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
              ),
            );
          },
        ),
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
      backgroundColor: AppColors.surface,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        minChildSize: 0.35,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            Text('审计详情', style: TextStyle(fontSize: fs + 1, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 8),
            SelectableText(cmd, style: TextStyle(fontFamily: 'monospace', fontSize: fs - 1, color: AppColors.textCode)),
            const SizedBox(height: 10),
            Text('风险 $risk · exit ${e['exitCode']} · $hostName', style: TextStyle(fontSize: fs - 2, color: AppColors.textMuted)),
            if (at.isNotEmpty) Text(at, style: TextStyle(fontSize: fs - 2, color: AppColors.textMuted, fontFamily: 'monospace')),
            if (stdout.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('stdout', style: TextStyle(fontSize: fs - 2, fontWeight: FontWeight.w700, color: AppColors.success)),
              const SizedBox(height: 4),
              SelectableText(stdout, style: TextStyle(fontFamily: 'monospace', fontSize: fs - 2, color: AppColors.textCode)),
            ],
            if (stderr.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('stderr', style: TextStyle(fontSize: fs - 2, fontWeight: FontWeight.w700, color: AppColors.danger)),
              const SizedBox(height: 4),
              SelectableText(stderr, style: TextStyle(fontFamily: 'monospace', fontSize: fs - 2, color: AppColors.dangerSoft)),
            ],
          ],
        ),
      ),
    );
  }
}
