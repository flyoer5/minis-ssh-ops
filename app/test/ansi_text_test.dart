import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_agent/pages/ansi_text.dart';

void main() {
  test('strips bracketed paste mode ESC[?2004h', () {
    final raw = '\x1B[?2004hroot@host:~# \n\x1B[?2004l';
    final plain = stripAnsi(raw);
    expect(plain.contains('2004'), isFalse);
    expect(plain.contains('?'), isFalse);
    expect(plain.contains('root@host'), isTrue);
  });

  test('strips alt-screen and application keypad noise', () {
    final raw = '\x1B[?1049h\x1B=hello\x1B>\x1B[?1049l';
    final plain = stripAnsi(raw);
    expect(plain.contains('1049'), isFalse);
    expect(plain.contains('hello'), isTrue);
  });

  test('AnsiPainter does not leak private mode text', () {
    final raw = '\x1B[?2004hroot@iZ4b7992okxrztZ:~# ';
    final span = AnsiPainter().build(raw);
    final buf = StringBuffer();
    void walk(InlineSpan s) {
      if (s is TextSpan) {
        if (s.text != null) buf.write(s.text);
        final kids = s.children;
        if (kids != null) {
          for (final c in kids) {
            walk(c);
          }
        }
      }
    }
    walk(span);
    final t = buf.toString();
    expect(t.contains('2004'), isFalse);
    expect(t.startsWith('root@'), isTrue);
  });
}
