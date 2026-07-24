import 'package:flutter/material.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';

/// Minimal SGR ANSI → [TextSpan] renderer for the PTY view.
/// Supports: reset, bold, dim, underline, 30–37 / 90–97 fg, 40–47 / 100–107 bg,
/// 38;5;n / 48;5;n (xterm-256 basic mapping), 38;2;r;g;b / 48;2;r;g;b.
class AnsiPainter {
  AnsiPainter({
    this.fontSize = 13,
    this.fontFamily = 'monospace',
    this.defaultFg = AppColors.slateLine,
    this.defaultBg,
  });

  final double fontSize;
  final String fontFamily;
  final Color defaultFg;
  final Color? defaultBg;

  static const _basic = <Color>[
    Color(0xFF000000), // 0 black
    Color(0xFFCD3131), // 1 red
    Color(0xFF0DBC79), // 2 green
    Color(0xFFE5E510), // 3 yellow
    Color(0xFF2472C8), // 4 blue
    Color(0xFFBC3FBC), // 5 magenta
    Color(0xFF11A8CD), // 6 cyan
    Color(0xFFE5E5E5), // 7 white
  ];
  static const _bright = <Color>[
    Color(0xFF666666),
    Color(0xFFF14C4C),
    Color(0xFF23D18B),
    Color(0xFFF5F543),
    Color(0xFF3B8EEA),
    Color(0xFFD670D6),
    Color(0xFF29B8DB),
    Color(0xFFFFFFFF),
  ];

  Color _xterm256(int n) {
    if (n < 0) return defaultFg;
    if (n < 8) return _basic[n];
    if (n < 16) return _bright[n - 8];
    if (n < 232) {
      // 6x6x6 cube
      final i = n - 16;
      final r = i ~/ 36, g = (i % 36) ~/ 6, b = i % 6;
      int c(int v) => v == 0 ? 0 : 55 + v * 40;
      return Color.fromARGB(255, c(r), c(g), c(b));
    }
    // grayscale 232–255
    final v = 8 + (n - 232) * 10;
    return Color.fromARGB(255, v, v, v);
  }

  TextSpan build(String raw) {
    // Drop OSC / charset / other non-SGR CSI first; keep SGR for color.
    var s = raw
        .replaceAll(RegExp(r'\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)?'), '')
        .replaceAll(RegExp(r'\x1B[()][0-9A-Za-z]'), '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    final spans = <TextSpan>[];
    var bold = false, dim = false, underline = false;
    Color? fg;
    Color? bg;

    TextStyle style() {
      var color = fg ?? defaultFg;
      if (dim) {
        color = Color.fromARGB(
          color.alpha,
          (color.red * 0.65).round(),
          (color.green * 0.65).round(),
          (color.blue * 0.65).round(),
        );
      }
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: 1.25,
        color: color,
        backgroundColor: bg,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        decoration: underline ? TextDecoration.underline : TextDecoration.none,
      );
    }

    void emit(String text) {
      if (text.isEmpty) return;
      // handle backspace / DEL simply on the pending buffer of last span is hard;
      // apply globally on plain text segments only.
      spans.add(TextSpan(text: text, style: style()));
    }

    final re = RegExp(r'\x1B\[([0-9;]*)([A-Za-z])|\x1B.');
    var i = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > i) {
        emit(_sanitizePlain(s.substring(i, m.start)));
      }
      final full = m.group(0)!;
      if (full.startsWith('\x1B[') && m.groupCount >= 2) {
        final params = m.group(1) ?? '';
        final cmd = m.group(2) ?? '';
        if (cmd == 'm') {
          final parts = params.isEmpty ? <String>['0'] : params.split(';');
          var pi = 0;
          while (pi < parts.length) {
            final n = int.tryParse(parts[pi]) ?? 0;
            switch (n) {
              case 0:
                bold = false;
                dim = false;
                underline = false;
                fg = null;
                bg = null;
                break;
              case 1:
                bold = true;
                break;
              case 2:
                dim = true;
                break;
              case 4:
                underline = true;
                break;
              case 22:
                bold = false;
                dim = false;
                break;
              case 24:
                underline = false;
                break;
              case 39:
                fg = null;
                break;
              case 49:
                bg = null;
                break;
              default:
                if (n >= 30 && n <= 37) {
                  fg = _basic[n - 30];
                } else if (n >= 90 && n <= 97) {
                  fg = _bright[n - 90];
                } else if (n >= 40 && n <= 47) {
                  bg = _basic[n - 40].withAlpha(0x66);
                } else if (n >= 100 && n <= 107) {
                  bg = _bright[n - 100].withAlpha(0x66);
                } else if (n == 38 || n == 48) {
                  final isFg = n == 38;
                  if (pi + 1 < parts.length) {
                    final mode = int.tryParse(parts[pi + 1]) ?? -1;
                    if (mode == 5 && pi + 2 < parts.length) {
                      final idx = int.tryParse(parts[pi + 2]) ?? 0;
                      final c = _xterm256(idx);
                      if (isFg) {
                        fg = c;
                      } else {
                        bg = c.withAlpha(0x66);
                      }
                      pi += 2;
                    } else if (mode == 2 && pi + 4 < parts.length) {
                      final r = int.tryParse(parts[pi + 2]) ?? 0;
                      final g = int.tryParse(parts[pi + 3]) ?? 0;
                      final b = int.tryParse(parts[pi + 4]) ?? 0;
                      final c = Color.fromARGB(255, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
                      if (isFg) {
                        fg = c;
                      } else {
                        bg = c.withAlpha(0x66);
                      }
                      pi += 4;
                    } else {
                      pi += 1;
                    }
                  }
                }
            }
            pi++;
          }
        }
        // ignore cursor / erase CSI letters for now (not replaying full TTY)
      }
      // bare ESC. already skipped by non-SGR branch
      i = m.end;
    }
    if (i < s.length) {
      emit(_sanitizePlain(s.substring(i)));
    }
    if (spans.isEmpty) {
      return TextSpan(text: '', style: style());
    }
    return TextSpan(children: spans, style: TextStyle(fontFamily: fontFamily, fontSize: fontSize, height: 1.25, color: defaultFg));
  }

  String _sanitizePlain(String s) {
    final out = StringBuffer();
    for (final cu in s.codeUnits) {
      if (cu == 0x09 || cu == 0x0A) {
        out.writeCharCode(cu);
      } else if (cu == 0x08 || cu == 0x7F) {
        final cur = out.toString();
        if (cur.isNotEmpty && !cur.endsWith('\n')) {
          out
            ..clear()
            ..write(cur.substring(0, cur.length - 1));
        }
      } else if (cu == 0xFFFD) {
        // skip
      } else if (cu >= 0x80 && cu <= 0x9F) {
        // C1
      } else if (cu >= 0x20 && cu != 0x7F) {
        out.writeCharCode(cu);
      }
    }
    return out.toString();
  }
}

/// Drop ANSI / controls and return plain text (clipboard / search).
String stripAnsi(String s) {
  var t = s
      .replaceAll(RegExp(r'\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)?'), '')
      .replaceAll(RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]'), '')
      .replaceAll(RegExp(r'\x1B[()][0-9A-Za-z]'), '')
      .replaceAll(RegExp(r'\x1B.'), '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final out = StringBuffer();
  for (final cu in t.codeUnits) {
    if (cu == 0x09 || cu == 0x0A || (cu >= 0x20 && cu != 0x7F && cu != 0xFFFD && !(cu >= 0x80 && cu <= 0x9F))) {
      out.writeCharCode(cu);
    }
  }
  return out.toString();
}
