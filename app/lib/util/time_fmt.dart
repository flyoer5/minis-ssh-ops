/// Time helpers for 机枢.
///
/// Backend stores RFC3339 UTC. Some Android/PRoot environments report a broken
/// local zone (e.g. `TZ=LCL-8` or missing zoneinfo), so [DateTime.toLocal] can
/// be wrong. We format in fixed UTC+8 (China) for display.
library;

/// Parse API time into wall clock time in China (UTC+8).
///
/// Zoned values are converted to UTC+8. Values without a zone are treated as
/// China wall clock values so the device time zone cannot shift them again.
DateTime? parseAsChina(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(value);
  if (!hasZone) {
    return DateTime(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    );
  }
  return parsed.toUtc().add(const Duration(hours: 8));
}

/// Parse persisted/API time into an instant suitable for comparisons.
///
/// Values without a zone are treated as China wall clock values and converted
/// to UTC, avoiding dependence on the Android device time zone.
DateTime? parseChinaInstant(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(value);
  if (hasZone) return parsed.toUtc();
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour - 8,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  );
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
