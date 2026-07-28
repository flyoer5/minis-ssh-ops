import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_agent/api/backend_url.dart';

void main() {
  test('allows HTTPS backend URLs', () {
    expect(validateBackendBaseUrl('https://ops.example.com/api').toString(), 'https://ops.example.com/api');
  });

  test('allows loopback HTTP URLs', () {
    for (final url in ['http://localhost:17890', 'http://127.0.0.1:17890', 'http://[::1]:17890']) {
      expect(validateBackendBaseUrl(url).scheme, 'http');
    }
  });

  test('rejects remote cleartext HTTP URLs', () {
    expect(() => validateBackendBaseUrl('http://192.168.1.8:17890'), throwsArgumentError);
    expect(() => validateBackendBaseUrl('http://ops.example.com'), throwsArgumentError);
  });

  test('rejects malformed and unsupported URLs', () {
    expect(() => validateBackendBaseUrl('ops.example.com'), throwsArgumentError);
    expect(() => validateBackendBaseUrl('ftp://ops.example.com'), throwsArgumentError);
  });
}