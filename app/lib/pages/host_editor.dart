import 'package:flutter/material.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';

/// Result of [showHostEditor].
class HostEditorResult {
  const HostEditorResult(this.body);
  final Map<String, dynamic> body;
}

/// Add / edit host with password or PEM private key auth.
Future<HostEditorResult?> showHostEditor(
  BuildContext context, {
  required String title,
  Map<String, dynamic>? existing,
}) async {
  final isEdit = existing != null;
  final name = TextEditingController(text: (existing?['name'] as String?) ?? '');
  final host = TextEditingController(text: (existing?['host'] as String?) ?? '');
  final port = TextEditingController(text: '${existing?['port'] ?? 22}');
  final user = TextEditingController(text: (existing?['username'] as String?) ?? 'root');
  final password = TextEditingController();
  final privateKey = TextEditingController();
  final passphrase = TextEditingController();
  final form = GlobalKey<FormState>();

  // 0 = password, 1 = private key
  var authMode = 0;
  if (isEdit && existing['hasPrivateKey'] == true && existing['hasPassword'] != true) {
    authMode = 1;
  }

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 4,
          bottom: MediaQuery.viewInsetsOf(c).bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (context, setLocal) {
            return Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: '名称（可选）'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: host,
                      decoration: const InputDecoration(labelText: '地址'),
                      validator: (v) => v == null || v.trim().isEmpty ? '必填' : null,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: user,
                            decoration: const InputDecoration(labelText: '用户'),
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: port,
                            decoration: const InputDecoration(labelText: '端口'),
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('认证方式', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('密码'), icon: Icon(Icons.password, size: 16)),
                        ButtonSegment(value: 1, label: Text('私钥'), icon: Icon(Icons.vpn_key, size: 16)),
                      ],
                      selected: {authMode},
                      onSelectionChanged: (s) {
                        if (s.isEmpty) return;
                        setLocal(() => authMode = s.first);
                      },
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                      ),
                    ),
                    if (isEdit) ...[
                      const SizedBox(height: 6),
                      Text(
                        _secretHint(existing, authMode),
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (authMode == 0)
                      TextFormField(
                        controller: password,
                        decoration: InputDecoration(
                          labelText: isEdit ? '密码（留空不改）' : '密码',
                        ),
                        obscureText: true,
                        validator: (v) {
                          if (isEdit) return null;
                          if (v == null || v.isEmpty) return '请填写密码，或改用私钥';
                          return null;
                        },
                      )
                    else ...[
                      TextFormField(
                        controller: privateKey,
                        decoration: InputDecoration(
                          labelText: isEdit ? '私钥 PEM（留空不改）' : '私钥 PEM',
                          alignLabelWithHint: true,
                          hintText: '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
                        ),
                        minLines: 4,
                        maxLines: 8,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                        validator: (v) {
                          if (isEdit) return null;
                          if (v == null || v.trim().isEmpty) return '请粘贴私钥，或改用密码';
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: passphrase,
                        decoration: InputDecoration(
                          labelText: isEdit ? '密钥口令（可选，留空不改）' : '密钥口令（可选）',
                        ),
                        obscureText: true,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            if (form.currentState?.validate() != true) return;
                            Navigator.pop(c, true);
                          },
                          child: Text(isEdit ? '保存' : '添加'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );

  if (ok != true) {
    name.dispose();
    host.dispose();
    port.dispose();
    user.dispose();
    password.dispose();
    privateKey.dispose();
    passphrase.dispose();
    return null;
  }

  final body = <String, dynamic>{
    'name': name.text.trim(),
    'host': host.text.trim(),
    'port': int.tryParse(port.text.trim()) ?? 22,
    'username': user.text.trim(),
  };
  if (authMode == 0) {
    if (password.text.isNotEmpty) body['password'] = password.text;
  } else {
    if (privateKey.text.trim().isNotEmpty) {
      body['privateKeyPem'] = privateKey.text.trim();
    }
    if (passphrase.text.isNotEmpty) body['passphrase'] = passphrase.text;
  }

  name.dispose();
  host.dispose();
  port.dispose();
  user.dispose();
  password.dispose();
  privateKey.dispose();
  passphrase.dispose();

  if (!isEdit) {
    final hasPw = (body['password'] as String?)?.isNotEmpty == true;
    final hasKey = (body['privateKeyPem'] as String?)?.isNotEmpty == true;
    if (!hasPw && !hasKey) return null;
  }

  return HostEditorResult(body);
}

String _secretHint(Map<String, dynamic>? existing, int authMode) {
  if (existing == null) return '';
  final hasPw = existing['hasPassword'] == true;
  final hasKey = existing['hasPrivateKey'] == true;
  if (authMode == 0) {
    return hasPw ? '已保存密码；填写则覆盖' : '当前无密码';
  }
  return hasKey ? '已保存私钥；粘贴新 PEM 则覆盖' : '当前无私钥';
}
