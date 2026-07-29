part of 'hosts_page.dart';

extension _StatusCardDataHelpers on _StatusCard {
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
    if (summary == null) return '-';
    for (final line in summary!.lines) {
      if (line.label == label) {
        final value = line.value.trim();
        return (value.isEmpty || value == '-') ? '-' : value;
      }
    }
    return '-';
  }

  double? _pct(String value) {
    final match = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(value);
    if (match != null) {
      return (double.tryParse(match.group(1)!) ?? 0).clamp(0, 100) / 100.0;
    }

    final parts = value.split('/');
    if (parts.length != 2) return null;

    double? parse(String raw) {
      final normalized = raw.trim().toUpperCase();
      final match = RegExp(r'([\d.]+)\s*([KMGT]?I?B?)').firstMatch(normalized);
      if (match == null) return null;
      var amount = double.tryParse(match.group(1)!) ?? 0;
      final unit = match.group(2) ?? '';
      if (unit.startsWith('T')) {
        amount *= 1024 * 1024;
      } else if (unit.startsWith('G')) {
        amount *= 1024;
      } else if (unit.startsWith('K')) {
        amount /= 1024;
      }
      return amount;
    }

    final used = parse(parts[0]);
    final total = parse(parts[1]);
    if (used != null && total != null && total > 0) {
      return (used / total).clamp(0.0, 1.0);
    }
    return null;
  }

  Color _barColor(double? progress) {
    if (progress == null) return AppColors.slate;
    if (progress >= 0.9) return AppColors.dangerAlt;
    if (progress >= 0.75) return AppColors.warnAlt;
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
    final oneLine = summary!.oneLine.trim();
    if (oneLine.isEmpty || oneLine == '-' || oneLine == '离线' || oneLine.toLowerCase() == 'offline') {
      return '离线';
    }
    if (oneLine.startsWith('错误') || oneLine.toLowerCase().contains('ssh') || oneLine.length > 24) {
      return '离线';
    }
    return oneLine;
  }
}
