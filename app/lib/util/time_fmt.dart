/// Time helpers for 机枢.
///
/// Backend stores RFC3339 UTC. Some Android/PRoot environments report a broken
/// local zone (e.g. `TZ=LCL-8` or missing zoneinfo), so [DateTime.toLocal] can
/// be wrong. We format in fixed UTC+8 (China) for display.
library;

/// Parse API time (UTC RFC3339 or local-ish) → wall clock in China (UTC+8).
DateTime? parseAsChina(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  var dt = DateTime.tryParse(s);
  if (dt == null) return null;
  // If string has no zone, DateTime.tryParse treats as local — still convert via UTC.
  final utc = dt.isUtc ? dt : dt.toUtc();
  return utc.add(const Duration(hours: 8));
}

String two(int n) => n.toString().padLeft(2, '0');

/// Absolute: 2026-07-25 14:30:00 (China)
String formatChinaAbsolute(String? raw) {
  final dt = parseAsChina(raw);
  if (dt == null) return (raw ?? '').trim();
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
}

/// Relative-friendly China wall time.
String formatChinaRelative(String? raw, {DateTime? nowChina}) {
  final dt = parseAsChina(raw);
  if (dt == null) return (raw ?? '').trim();
  final now = nowChina ?? DateTime.now().toUtc().add(const Duration(hours: 8));
  final diff = now.difference(dt);
  if (diff.isNegative || diff.inSeconds < 45) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24 && now.day == dt.day) {
    return '今天 ${two(dt.hour)}:${two(dt.minute)}';
  }
  final yday = now.subtract(const Duration(days: 1));
  if (yday.year == dt.year && yday.month == dt.month && yday.day == dt.day) {
    return '昨天 ${two(dt.hour)}:${two(dt.minute)}';
  }
  if (now.year == dt.year) {
    return '${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
  return formatChinaAbsolute(raw);
}

/// Relative for DateTime already in hand (assumed UTC or local → via UTC+8).
String formatChinaRelativeDt(DateTime when) {
  final utc = when.isUtc ? when : when.toUtc();
  final china = utc.add(const Duration(hours: 8));
  final now = DateTime.now().toUtc().add(const Duration(hours: 8));
  final diff = now.difference(china);
  if (diff.isNegative || diff.inSeconds < 45) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24 && now.day == china.day) {
    return '今天 ${two(china.hour)}:${two(china.minute)}';
  }
  final yday = now.subtract(const Duration(days: 1));
  if (yday.year == china.year && yday.month == china.month && yday.day == china.day) {
    return '昨天 ${two(china.hour)}:${two(china.minute)}';
  }
  if (now.year == china.year) {
    return '${two(china.month)}-${two(china.day)} ${two(china.hour)}:${two(china.minute)}';
  }
  return '${china.year}-${two(china.month)}-${two(china.day)} ${two(china.hour)}:${two(china.minute)}';
}
