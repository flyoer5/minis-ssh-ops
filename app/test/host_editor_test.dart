import 'package:flutter_test/flutter_test.dart';

/// Pure helpers mirroring host editor body rules (UI tested via integration later).
Map<String, dynamic> buildHostBody({
  required String name,
  required String host,
  required int port,
  required String username,
  required int authMode, // 0 password 1 key
  String password = '',
  String privateKeyPem = '',
  String passphrase = '',
  bool isEdit = false,
}) {
  final body = <String, dynamic>{
    'name': name.trim(),
    'host': host.trim(),
    'port': port,
    'username': username.trim(),
  };
  if (authMode == 0) {
    if (password.isNotEmpty) body['password'] = password;
  } else {
    if (privateKeyPem.trim().isNotEmpty) body['privateKeyPem'] = privateKeyPem.trim();
    if (passphrase.isNotEmpty) body['passphrase'] = passphrase;
  }
  return body;
}

bool hostBodyHasAuth(Map<String, dynamic> body) {
  final hasPw = (body['password'] as String?)?.isNotEmpty == true;
  final hasKey = (body['privateKeyPem'] as String?)?.isNotEmpty == true;
  return hasPw || hasKey;
}

void main() {
  test('password auth body', () {
    final b = buildHostBody(
      name: 'vps',
      host: '1.2.3.4',
      port: 22,
      username: 'root',
      authMode: 0,
      password: 's3cret',
    );
    expect(b['password'], 's3cret');
    expect(b.containsKey('privateKeyPem'), isFalse);
    expect(hostBodyHasAuth(b), isTrue);
  });

  test('private key auth body with passphrase', () {
    final b = buildHostBody(
      name: '',
      host: 'box.local',
      port: 2222,
      username: 'ubuntu',
      authMode: 1,
      privateKeyPem: '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----',
      passphrase: 'pp',
    );
    expect(b['port'], 2222);
    expect(b['privateKeyPem'], contains('BEGIN OPENSSH'));
    expect(b['passphrase'], 'pp');
    expect(b.containsKey('password'), isFalse);
    expect(hostBodyHasAuth(b), isTrue);
  });

  test('edit leave secrets empty', () {
    final b = buildHostBody(
      name: 'x',
      host: 'h',
      port: 22,
      username: 'u',
      authMode: 0,
      password: '',
      isEdit: true,
    );
    expect(b.containsKey('password'), isFalse);
    // create would reject; edit may only change name
    expect(hostBodyHasAuth(b), isFalse);
  });
}
