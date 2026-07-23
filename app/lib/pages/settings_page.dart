import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with AutomaticKeepAliveClientMixin {
  final baseUrl = TextEditingController(text: 'http://127.0.0.1:17890');
  final token = TextEditingController();
  final llmBase = TextEditingController();
  final llmKey = TextEditingController();
  final llmModel = TextEditingController(text: 'grok-4.5');
  bool loaded = false;
  String? pingMsg;
  bool pinging = false;
  List<String> _modelIds = [];
  bool _loadingModels = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loaded) return;
    loaded = true;
    final s = context.read<AppState>();
    baseUrl.text = s.api.baseUrl;
    token.text = s.api.localToken;
    final llm = s.llm;
    if (llm != null) {
      llmBase.text = (llm['baseUrl'] as String?) ?? '';
      llmModel.text = (llm['model'] as String?) ?? 'grok-4.5';
      final k = llm['apiKey']?.toString();
      if (k != null && k.isNotEmpty) llmKey.text = k;
    }
    if (s.backendOk) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshModels(s));
    }
  }

  @override
  void dispose() {
    baseUrl.dispose();
    token.dispose();
    llmBase.dispose();
    llmKey.dispose();
    llmModel.dispose();
    super.dispose();
  }

  Future<void> _refreshModels(AppState state) async {
    if (!state.backendOk || _loadingModels) return;
    setState(() => _loadingModels = true);
    try {
      final ids = await state.fetchModels();
      if (!mounted) return;
      setState(() {
        _modelIds = ids;
        if (llmModel.text.isEmpty && ids.isNotEmpty) llmModel.text = ids.first;
      });
    } catch (e) {
      if (mounted) _toast('拉取模型列表失败: $e');
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          _section('关于', [
            Text('SSH AI Agent 1.4.4', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('个人向 · arm64 · 固定签名可覆盖升级', style: TextStyle(fontSize: 12, color: Color(0xFF8B949E))),
          ]),
          _section('后端', [
            Text(
              state.backendOk ? '已连接 · ${state.api.baseUrl}' : '未连接',
              style: TextStyle(color: state.backendOk ? const Color(0xFF3FB950) : const Color(0xFFF85149)),
            ),
            if (state.backendNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(state.backendNote!, style: const TextStyle(fontSize: 12, color: Color(0xFF8B949E))),
              ),
            TextField(controller: baseUrl, decoration: const InputDecoration(labelText: 'Go Base URL')),
            TextField(controller: token, decoration: const InputDecoration(labelText: 'X-Local-Token')),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                try {
                  await state.saveConnection(baseUrl: baseUrl.text.trim(), token: token.text.trim());
                  _toast(state.backendOk ? '已连接' : '失败: ${state.backendError}');
                } catch (e) {
                  _toast('$e');
                }
              },
              child: const Text('保存并连接'),
            ),
          ]),
          _section('大模型', [
            TextField(controller: llmBase, decoration: const InputDecoration(labelText: 'LLM Base URL', helperText: 'OpenAI 兼容，含 /v1')),
            TextField(
              controller: llmKey,
              decoration: const InputDecoration(labelText: 'API Key', helperText: '本地明文保存，不脱敏'),
              obscureText: false,
              enableSuggestions: false,
              autocorrect: false,
            ),
            Row(
              children: [
                Expanded(
                  child: _modelIds.isEmpty
                      ? TextField(
                          controller: llmModel,
                          decoration: const InputDecoration(labelText: '模型', helperText: '可点右侧刷新拉取列表'),
                        )
                      : DropdownButtonFormField<String>(
                          value: _modelIds.contains(llmModel.text) ? llmModel.text : null,
                          decoration: const InputDecoration(labelText: '模型'),
                          items: [
                            for (final id in _modelIds)
                              DropdownMenuItem(value: id, child: Text(id, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => llmModel.text = v);
                          },
                        ),
                ),
                IconButton(
                  tooltip: '拉取模型列表',
                  onPressed: !state.backendOk || _loadingModels ? null : () => _refreshModels(state),
                  icon: _loadingModels
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_modelIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Text('共 ${_modelIds.length} 个模型', style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E))),
              ),
            FilledButton.tonal(
              onPressed: !state.backendOk
                  ? null
                  : () async {
                      try {
                        await state.saveLlm(baseUrl: llmBase.text.trim(), model: llmModel.text.trim(), apiKey: llmKey.text);
                        await _refreshModels(state);
                        _toast('LLM 已保存');
                      } catch (e) {
                        _toast('$e');
                      }
                    },
              child: const Text('保存 LLM'),
            ),
          ]),
          _section('连通性', [
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonal(
                onPressed: !state.backendOk || state.selectedHostId == null || pinging
                    ? null
                    : () async {
                        setState(() { pinging = true; pingMsg = null; });
                        try {
                          final o = await state.testHostSsh();
                          setState(() => pingMsg = 'SSH OK: $o');
                        } catch (e) {
                          setState(() => pingMsg = 'SSH 失败: $e');
                        } finally {
                          setState(() => pinging = false);
                        }
                      },
                child: const Text('测 SSH'),
              ),
              FilledButton.tonal(
                onPressed: !state.backendOk || state.selectedHostId == null || pinging
                    ? null
                    : () async {
                        setState(() { pinging = true; pingMsg = null; });
                        try {
                          final o = await state.testLlmReachable();
                          setState(() => pingMsg = o);
                        } catch (e) {
                          setState(() => pingMsg = '模型失败: $e');
                        } finally {
                          setState(() => pinging = false);
                        }
                      },
                child: const Text('测模型'),
              ),
              if (pinging) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            if (pingMsg != null) ...[
              const SizedBox(height: 8),
              SelectableText(pingMsg!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ],
          ]),
          _section('保活', [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('忽略电池优化'),
              subtitle: Text(state.batteryIgnored ? '已忽略（有利于后台）' : '未忽略，后台易被杀'),
              trailing: TextButton(
                onPressed: () async {
                  await state.requestBatteryExempt();
                  _toast(state.batteryIgnored ? '已忽略' : '请在系统页确认');
                },
                child: const Text('去设置'),
              ),
            ),
            TextButton(onPressed: () => state.openBatterySettings(), child: const Text('打开电池优化列表')),
          ]),
          _section('Agent', [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('写操作需确认'),
              subtitle: const Text('开启后，写/破坏类命令需点运行'),
              value: state.confirmWrites,
              onChanged: (v) => state.setConfirmWrites(v),
            ),
          ]),
          _section('终端', [
            Row(
              children: [
                const Text('字体'),
                Expanded(
                  child: Slider(
                    value: state.termFontSize,
                    min: 10,
                    max: 20,
                    divisions: 10,
                    label: state.termFontSize.toStringAsFixed(0),
                    onChanged: (v) => state.setTermFontSize(v),
                  ),
                ),
                Text(state.termFontSize.toStringAsFixed(0)),
              ],
            ),
            const Text('终端页也可点 A+/A- 调整', style: TextStyle(fontSize: 11, color: Color(0xFF8B949E))),
          ]),
          _section('诊断', [
            FilledButton.tonal(
              onPressed: !state.backendOk ? null : () async {
                try {
                  final json = await state.exportConfigJson();
                  if (!context.mounted) return;
                  await showDialog(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('导出配置'),
                      content: SizedBox(
                        width: double.maxFinite,
                        height: 280,
                        child: SelectableText(json, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      ),
                      actions: [
                        TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: json)); Navigator.pop(c); _toast('已复制'); }, child: const Text('复制')),
                        TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
                      ],
                    ),
                  );
                } catch (e) {
                  _toast('$e');
                }
              },
              child: const Text('导出配置'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: !state.backendOk ? null : () async {
                final ctrl = TextEditingController();
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('导入配置 JSON'),
                    content: TextField(controller: ctrl, maxLines: 12, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('导入')),
                    ],
                  ),
                );
                if (ok == true) {
                  try {
                    _toast(await state.importConfigJson(ctrl.text));
                  } catch (e) {
                    _toast('$e');
                  }
                }
              },
              child: const Text('导入配置'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () async {
                final log = await state.exportBackendLog();
                if (!context.mounted) return;
                await showDialog(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('backend.log'),
                    content: SizedBox(
                      width: double.maxFinite,
                      height: 360,
                      child: SingleChildScrollView(
                        child: SelectableText(log.isEmpty ? '(empty)' : log, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: log)); Navigator.pop(c); }, child: const Text('复制关闭')),
                      TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
                    ],
                  ),
                );
              },
              child: const Text('查看后端日志'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: !state.backendOk ? null : () async {
                try {
                  final r = await state.api.listKnownHosts();
                  final entries = (r['entries'] as List?) ?? [];
                  if (!context.mounted) return;
                  await showDialog(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('已知主机密钥 (TOFU)'),
                      content: SizedBox(
                        width: double.maxFinite,
                        height: 320,
                        child: entries.isEmpty
                            ? const Center(child: Text('暂无记录'))
                            : ListView.builder(
                                itemCount: entries.length,
                                itemBuilder: (_, i) {
                                  final e = entries[i] as Map;
                                  final host = e['host']?.toString() ?? '';
                                  final port = e['port'] is int ? e['port'] as int : int.tryParse('${e['port']}') ?? 22;
                                  final fp = e['fingerprint']?.toString() ?? '';
                                  return ListTile(
                                    dense: true,
                                    title: Text('$host:$port', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                                    subtitle: Text(fp, maxLines: 2, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18),
                                      onPressed: () async {
                                        await state.api.deleteKnownHost(host, port);
                                        if (c.mounted) Navigator.pop(c);
                                        _toast('已删除，下次连接将重新信任');
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
                    ),
                  );
                } catch (e) {
                  _toast('$e');
                }
              },
              child: const Text('管理 HostKey'),
            ),
          ]),
        ],
      ),
    );
  }
}
