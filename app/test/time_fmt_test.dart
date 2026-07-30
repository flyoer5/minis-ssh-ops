import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_agent/util/time_fmt.dart';

void main() {
  group('北京时间解析', () {
    test('UTC 时间转换为东八区', () {
      final time = parseAsChina('2026-07-30T04:05:06Z');
      expect(
        [time?.year, time?.month, time?.day, time?.hour, time?.minute, time?.second],
        [2026, 7, 30, 12, 5, 6],
      );
    });

    test('带东八区偏移的时间保持北京时间', () {
      final time = parseAsChina('2026-07-30T12:05:06+08:00');
      expect(
        [time?.year, time?.month, time?.day, time?.hour, time?.minute, time?.second],
        [2026, 7, 30, 12, 5, 6],
      );
    });

    test('无时区时间直接按北京时间解释', () {
      expect(
        parseAsChina('2026-07-30 12:05:06'),
        DateTime(2026, 7, 30, 12, 5, 6),
      );
    });

    test('无时区持久化时间按北京时间转换为 UTC 瞬间', () {
      expect(
        parseChinaInstant('2026-07-30 12:05:06'),
        DateTime.utc(2026, 7, 30, 4, 5, 6),
      );
      expect(
        parseChinaInstant('2026-07-30T12:05:06+08:00'),
        DateTime.utc(2026, 7, 30, 4, 5, 6),
      );
    });

    test('绝对时间使用中国常用 24 小时格式', () {
      expect(
        formatChinaAbsolute('2026-07-30T04:05:06Z'),
        '2026-07-30 12:05:06',
      );
    });

    test('相对时间使用中文日期表达', () {
      final now = DateTime(2026, 7, 30, 12, 30);
      expect(
        formatChinaRelative('2026-07-30T04:00:00Z', nowChina: now),
        '30 分钟前',
      );
      expect(
        formatChinaRelative('2026-07-29T04:00:00Z', nowChina: now),
        '昨天 12:00',
      );
    });
  });
}
