class ProbeLine {
  final String label;
  final String value;
  ProbeLine(this.label, this.value);
}

class ProbeSummary {
  final bool ok;
  final String oneLine;
  final List<ProbeLine> lines;
  final String detail;

  ProbeSummary({
    required this.ok,
    required this.oneLine,
    required this.lines,
    required this.detail,
  });

  factory ProbeSummary.fromProbeJson(Map<String, dynamic> res) {
    String pick(String key) {
      final v = res[key];
      if (v is Map) {
        if (v['error'] != null) return '错误: ${v['error']}';
        final s = (v['stdout'] ?? '').toString().trim();
        final e = (v['stderr'] ?? '').toString().trim();
        if (s.isNotEmpty) return s;
        if (e.isNotEmpty) return e;
        return 'exit ${v['exitCode']}';
      }
      if (v == null) return '-';
      return v.toString();
    }

    String firstLine(String s) {
      final t = s.trim();
      if (t.isEmpty) return '-';
      return t.split('\n').first.trim();
    }

    final uname = pick('uname');
    final uptime = pick('uptime');
    final disk = pick('disk');
    final memory = pick('memory');
    final load = pick('load');
    final cpuRaw = pick('cpu');

    final hasErr = [uname, uptime, disk, memory, load].any((s) => s.startsWith('错误:'));
    final ok = !hasErr && uname != '-';

    // loadavg kept for detail
    String loadHint = firstLine(load);
    final loadParts = loadHint.split(RegExp(r'\s+'));
    if (loadParts.isNotEmpty && double.tryParse(loadParts[0]) != null) {
      loadHint = loadParts.length >= 3
          ? '${loadParts[0]} / ${loadParts[1]} / ${loadParts[2]}'
          : loadParts[0];
    }

    // CPU utilization % from dual /proc/stat sample
    String cpuHint = '—';
    final cpuLine = firstLine(cpuRaw);
    final cpuN = int.tryParse(cpuLine) ?? double.tryParse(cpuLine)?.round();
    if (cpuN != null) {
      cpuHint = '${cpuN.clamp(0, 100)}%';
    }

    // disk: df -h root line → Filesystem Size Used Avail Use% /
    String diskHint = '—';
    String diskSub = '';
    for (final line in disk.split('\n')) {
      final cols = line.trim().split(RegExp(r'\s+'));
      if (cols.length >= 6 && cols.last == '/') {
        // last-2 is Use%, size=cols[1], used=cols[2] (when FS has no spaces)
        final pct = cols[cols.length - 2];
        diskHint = pct.contains('%') ? pct : '$pct%';
        if (cols.length >= 5) {
          // Prefer Size/Used from fixed positions when possible
          final size = cols[1];
          final used = cols[2];
          if (RegExp(r'^\d').hasMatch(size) && RegExp(r'^\d').hasMatch(used)) {
            diskSub = '$used/$size';
          } else {
            // long FS name: Use% is still last-2; skip size
            diskSub = '';
          }
        }
        break;
      }
    }
    if (diskHint == '—') {
      final m = RegExp(r'(\d+)%').firstMatch(disk);
      if (m != null) diskHint = '${m.group(1)}%';
    }

    // memory: free -h often starts with a header line, then "Mem: total used free ..."
    String memHint = '—';
    String memSub = '';
    String? memLine;
    for (final line in memory.split('\n')) {
      final t = line.trim();
      if (t.toLowerCase().startsWith('mem:')) {
        memLine = t;
        break;
      }
    }
    if (memLine != null) {
      final cols = memLine.split(RegExp(r'\s+'));
      // Mem: total used free shared buff/cache available
      if (cols.length >= 3) {
        final total = cols[1];
        final used = cols[2];
        memSub = '$used/$total';
        // percent from human sizes when possible
        double? toMi(String x) {
          final m = RegExp(r'([\d.]+)\s*([KMGT])?', caseSensitive: false).firstMatch(x.trim());
          if (m == null) return null;
          var n = double.tryParse(m.group(1)!) ?? 0;
          final u = (m.group(2) ?? '').toUpperCase();
          if (u == 'T') n *= 1024 * 1024;
          else if (u == 'G') n *= 1024;
          else if (u == 'K') n /= 1024;
          // M or bare: Mi already
          return n;
        }
        final u = toMi(used);
        final t = toMi(total);
        if (u != null && t != null && t > 0) {
          memHint = '${(u * 100 / t).round()}%';
        } else {
          memHint = used;
        }
      }
    } else {
      // MemTotal / MemAvailable kB
      final totalM = RegExp(r'MemTotal:\s+(\d+)').firstMatch(memory);
      final availM = RegExp(r'MemAvailable:\s+(\d+)').firstMatch(memory);
      if (totalM != null && availM != null) {
        final total = int.parse(totalM.group(1)!);
        final avail = int.parse(availM.group(1)!);
        final used = total - avail;
        final pct = total == 0 ? 0 : (used * 100 / total).round();
        memHint = '$pct%';
        memSub = '${(used / 1024 / 1024).toStringAsFixed(1)}G/${(total / 1024 / 1024).toStringAsFixed(1)}G';
      } else {
        memHint = firstLine(memory);
        // avoid showing free(1) header as value
        if (memHint.toLowerCase().contains('total') && memHint.toLowerCase().contains('used')) {
          memHint = '—';
        }
      }
    }

    // uptime shorten
    String upHint = firstLine(uptime);
    final upm = RegExp(r'up\s+([^,]+)').firstMatch(uptime);
    if (upm != null) upHint = upm.group(1)!.trim();

    // uname -a → short: sysname release machine
    String sys = firstLine(uname);
    {
      final parts = sys.split(RegExp(r'\s+'));
      if (parts.length >= 5) {
        final sysname = parts[0];
        final release = parts[2];
        String machine = '';
        for (var i = parts.length - 1; i >= 3; i--) {
          final p = parts[i];
          if (RegExp(r'^(x86_64|amd64|aarch64|arm64|armv\d+l?|i[3-6]86|riscv64|ppc64le|s390x)$', caseSensitive: false).hasMatch(p)) {
            machine = p;
            break;
          }
        }
        if (machine.isEmpty && parts.length >= 12) machine = parts[11];
        sys = machine.isEmpty ? '$sysname $release' : '$sysname $release $machine';
      } else if (sys.length > 48) {
        sys = '${sys.substring(0, 48)}…';
      }
    }
    final one = ok ? 'cpu $cpuHint · mem $memHint · disk $diskHint' : '离线';

    final lines = <ProbeLine>[
      ProbeLine('系统', sys),
      ProbeLine('CPU', cpuHint),
      ProbeLine('负载', loadHint),
      ProbeLine('磁盘', diskSub.isEmpty ? diskHint : '$diskHint ($diskSub)'),
      ProbeLine('内存', memSub.isEmpty ? memHint : '$memHint ($memSub)'),
      ProbeLine('运行', upHint),
      ProbeLine('CPU%', cpuHint),
      ProbeLine('磁盘%', diskHint),
      ProbeLine('内存主', memHint),
      ProbeLine('负载1', loadParts.isNotEmpty ? loadParts[0] : '—'),
    ];

    final detail = StringBuffer()
      ..writeln('uname:\n$uname\n')
      ..writeln('uptime:\n$uptime\n')
      ..writeln('cpu:\n$cpuRaw\n')
      ..writeln('load:\n$load\n')
      ..writeln('disk:\n$disk\n')
      ..writeln('memory:\n$memory\n');

    return ProbeSummary(
      ok: ok,
      oneLine: one,
      lines: lines,
      detail: detail.toString().trim(),
    );
  }
}
