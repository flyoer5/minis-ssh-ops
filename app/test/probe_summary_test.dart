import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:ssh_ai_agent/api/client.dart';

void main() {
  group('ProbeSummary.fromProbeJson', () {
    test('parses healthy probe payload', () {
      final s = ProbeSummary.fromProbeJson({
        'uname': {'stdout': 'Linux box 6.1.0-generic #1 SMP x86_64 GNU/Linux\n'},
        'uptime': {'stdout': ' 12:00:00 up 3 days,  4:05,  1 user,  load average: 0.10, 0.20, 0.30\n'},
        'load': {'stdout': '0.10 0.20 0.30 1/100 1\n'},
        'cpu': {'stdout': '12\n'},
        'disk': {
          'stdout':
              'Filesystem      Size  Used Avail Use% Mounted on\n'
              '/dev/sda1        40G   19G   19G  51% /\n'
        },
        'memory': {
          'stdout':
              '              total        used        free      shared  buff/cache   available\n'
              'Mem:           3.7Gi       1.2Gi       200Mi       4.0Mi       2.3Gi       2.3Gi\n'
        },
      });
      expect(s.ok, isTrue);
      expect(s.oneLine.contains('cpu'), isTrue);
      final cpu = s.lines.where((l) => l.label == 'CPU%' || l.label == 'CPU').map((l) => l.value).toList();
      expect(cpu.any((v) => v.contains('12')), isTrue);
      final disk = s.lines.where((l) => l.label == '磁盘%').map((l) => l.value).toList();
      expect(disk.any((v) => v.contains('51')), isTrue);
    });

    test('marks error when uname missing', () {
      final s = ProbeSummary.fromProbeJson({
        'uname': {'stdout': ''},
        'uptime': {'stdout': ''},
        'load': {'stdout': ''},
        'cpu': {'stdout': ''},
        'disk': {'stdout': ''},
        'memory': {'stdout': ''},
      });
      expect(s.ok, isFalse);
    });
  });

  group('friendlyProbeError', () {
    final state = AppState(ApiClient(baseUrl: 'http://127.0.0.1:9'));

    test('maps timeout', () {
      final f = state.friendlyProbeError(Exception('i/o timeout'));
      expect(f['short'], '超时');
    });

    test('maps auth failure', () {
      final f = state.friendlyProbeError(Exception('unable to authenticate, permission denied'));
      expect(f['short'], '认证失败');
    });

    test('maps connection refused', () {
      final f = state.friendlyProbeError(Exception('connect: connection refused'));
      expect(f['short'], '连接拒绝');
    });

    test('maps dns failure', () {
      final f = state.friendlyProbeError(Exception('no such host'));
      expect(f['short'], '域名解析失败');
    });

    test('fallback probe fail', () {
      final f = state.friendlyProbeError(Exception('weird boom'));
      expect(f['short'], '探测失败');
    });
  });
}
