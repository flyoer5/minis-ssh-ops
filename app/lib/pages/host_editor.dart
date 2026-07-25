import 'package:flutter/material.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
import 'package:ssh_ai_agent/widgets/ime_inset.dart';

/// Result of [showHostEditor].
class HostEditorResult {
  const HostEditorResult(this.body);
  final Map<String, dynamic> body;
}

/// Add / edit host with password or PEM private key auth.
///
/// Controllers live in a StatefulWidget so they are only disposed after the
/// modal route has fully unmounted — disposing immediately after pop caused
/// `_dependents.isEmpty` assertion crashes when the sheet still held listeners.
Future<HostEditorResult?> showHostEditor(
  BuildContext context, {
  required String title,
  Map<String, dynamic>? existing,
}) async {
  return showModalBottomSheet<HostEditorResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => _HostEditorSheet(title: title, existing: existing),
  );
}

class _HostEditorSheet extends StatefulWidget {
  const _HostEditorSheet({required this.title, this.existing});
  final String title;
  final Map<String, dynamic>? existing;

  @override
  State<_HostEditorSheet> createState() => _HostEditorSheetState();
}

class _HostEditorSheetState extends State<_HostEditorSheet> {
  late final TextEditingController name;
  late final TextEditingController host;
  late final TextEditingController port;
  late final TextEditingController user;
  late final TextEditingController password;
  late final TextEditingController privateKey;
  late final TextEditingController passphrase;
  final form = GlobalKey<FormState>();
  // 0 = password, 1 = private key
  late int authMode;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    name = TextEditingController(text: (existing?['name'] as String?) ?? '');
    host = TextEditingController(text: (existing?['host'] as String?) ?? '');
    port = TextEditingController(text: '${existing?['port'] ?? 22}');
    user = TextEditingController(text: (existing?['username'] as String?) ?? 'root');
    password = TextEditingController();
    privateKey = TextEditingController();
    passphrase = TextEditingController();
    authMode = 0;
    if (isEdit && existing!['hasPrivateKey'] == true && existing['hasPassword'] != true) {
      authMode = 1;
    }
  }

  @override
  void dispose() {
    name.dispose();
    host.dispose();
    port.dispose();
    user.dispose();
    password.dispose();
    privateKey.dispose();
    passphrase.dispose();
    super.dispose();
  }

  HostEditorResult? _buildResult() {
    if (form.currentState?.validate() != true) return null;
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
    if (!isEdit) {
      final hasPw = (body['password'] as String?)?.isNotEmpty == true;
      final hasKey = (body['privateKeyPem'] as String?)?.isNotEmpty == true;
      if (!hasPw && !hasKey) return null;
    }
    return HostEditorResult(body);
  }

  @override
  Widget build(BuildContext context) {
    // Sheet is small; ImeInset still avoids fighting the system IME curve.
    return ImeInset(
      left: 16,
      right: 16,
      top: 4,
      extraBottom: 16,
      child: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
                  setState(() => authMode = s.first);
                },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                ),
              ),
              if (isEdit) ...[
                const SizedBox(height: 6),
                Text(
                  _secretHint(widget.existing, authMode),
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
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      final result = _buildResult();
                      if (result == null) {
                        if (!isEdit && authMode == 0 && password.text.isEmpty) {
                          // validation already shows field errors
                        }
                        return;
                      }
                      Navigator.pop(context, result);
                    },
                    child: Text(isEdit ? '保存' : '添加'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
