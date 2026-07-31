import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_agent/api/client.dart';

void main() {
  test('API timeout uses concise Chinese message', () async {
    final api = ApiClient();
    addTearDown(api.dispose);

    Object? caught;
    try {
      await api.testTimeoutForTest(
        Completer<void>().future,
        const Duration(milliseconds: 1),
      );
    } catch (e) {
      caught = e;
    }

    expect(caught, isA<ApiTimeoutException>());
    expect(caught.toString(), '请求超时，请检查网络或主机连接');
  });
}
