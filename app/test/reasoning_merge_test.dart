import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_agent/agent/reasoning_merge.dart';

void main() {
  group('isSameOrSubReason', () {
    test('spaced vs glued English', () {
      const glued = 'Theusersaid你好.Thisisagreet.';
      const spaced = 'The user said 你好. This is a greet.';
      // compact forms differ if glue removed spaces between words incorrectly...
      // "Theusersaid" compact is theusersaid; spaced compact is theusersaid — same if only spaces differ
      expect(compactReason(spaced), 'theusersaid你好.thisisagreet.');
      expect(isSameOrSubReason(glued, spaced), isTrue);
    });

    test('identical', () {
      expect(isSameOrSubReason('hello world', 'hello world'), isTrue);
    });

    test('prefix stream draft', () {
      expect(isSameOrSubReason('hello', 'hello world'), isTrue);
    });

    test('different thoughts', () {
      expect(isSameOrSubReason('probe disk', 'restart nginx'), isFalse);
    });
  });

  group('preferReasoning', () {
    test('prefers spaced over glued', () {
      const glued = 'Theusersaid你好';
      const spaced = 'The user said 你好';
      final out = preferReasoning(glued, spaced);
      expect(out.contains(' '), isTrue);
      expect(out, spaced);
    });

    test('joins truly different segments', () {
      final out = preferReasoning('first thought', 'second thought');
      expect(out.contains('\n\n'), isTrue);
      expect(out, contains('first thought'));
      expect(out, contains('second thought'));
    });
  });

  group('mergeReasoningForTurn', () {
    test('empty current', () {
      expect(mergeReasoningForTurn(null, '  hello  '), 'hello');
    });

    test('stream then final does not double', () {
      const stream = 'Theusersaid你好.Thisisagreet.';
      const finalText = 'The user said 你好. This is a greet.';
      final once = mergeReasoningForTurn(stream, finalText);
      final twice = mergeReasoningForTurn(once, finalText);
      expect(once.contains('\n\n'), isFalse);
      expect(twice, once);
      expect(RegExp(r'\s').hasMatch(once), isTrue);
    });

    test('idempotent final', () {
      const t = 'Hello world';
      expect(mergeReasoningForTurn(t, t), t);
    });
  });
}
