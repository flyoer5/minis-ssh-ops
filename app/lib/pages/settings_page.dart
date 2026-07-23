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
  String thinkingLevel = 'auto';
  bool loaded = false;
  String? pingMsg;
  bool pinging = false;
  List<String> _modelIds = [];
  bool _loadingModels = false;
  bool _obscureKey = true;

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
      thinkingLevel = (llm['thinkingLevel'] as String?)?.toString() ?? 'auto';
      if (thinkingLevel.isEmpty) thinkingLevel = 'auto';
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

  Widget _section({
    required IconData icon,
    required Color accent,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accent.withAlpha(0x22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accent.withAlpha(0x55)),
                  ),
                  child: Icon(icon, size: 15, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                      if (subtitle != null)
                        Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E), height: 1.25)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF21262D)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fontSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Text(
                value.toStringAsFixed(0),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF79C0FF)),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).round(),
            label: value.toStringAsFixed(0),
            onChanged: onChanged,
          ),
        ),
        if (hint != null)
          Text(hint, style: const TextStyle(fontSize: 11, color: Color(0xFF6E7681))),
      ],
    );
  }

  Widget _statusChip(bool ok, String text) {
    final c = ok ? const Color(0xFF3FB950) : const Color(0xFFF85149);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withAlpha(0x18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withAlpha(0x66)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle : Icons.error_outline, size: 12, color: c),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        toolbarHeight: 44,
        backgroundColor: const Color(0xFF0D1117),
        titleSpacing: 12,
        title: const Text('设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
        children: [
          // —— 关于 ——
          _section(
            icon: Icons.info_outline,
            accent: const Color(0xFF58A6FF),
            title: '关于',
            subtitle: '个人向 · arm64 · 固定签名可覆盖升级',
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('SSH AI Agent', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F6FEB).withAlpha(0x33),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('1.4.9', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF79C0FF))),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '主机探针 · Agent · 终端 · SFTP · 审计',
                style: TextStyle(fontSize: 12, color: Color(0xFF8B949E)),
              ),
            ],
          ),

          // —— 后端 ——
          _section(
            icon: Icons.dns_outlined,
            accent: const Color(0xFF3FB950),
            title: '后端连接',
            subtitle: '本机 Go 服务地址与 Local Token',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _statusChip(state.backendOk, state.backendOk ? '已连接' : '未连接'),
                  if (state.backendOk)
                    Text(
                      state.api.baseUrl,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF8B949E)),
                    ),
                ],
              ),
              if (state.backendNote != null) ...[
                const SizedBox(height: 6),
                Text(state.backendNote!, style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E))),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: baseUrl,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  labelText: 'Go Base URL',
                  isDense: true,
                  prefixIcon: Icon(Icons.link, size: 18),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: token,
                style: const TextStyle(fontSize: 13.5, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'X-Local-Token',
                  isDense: true,
                  prefixIcon: Icon(Icons.key, size: 18),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () async {
                  try {
                    await state.saveConnection(baseUrl: baseUrl.text.trim(), token: token.text.trim());
                    _toast(state.backendOk ? '已连接' : '失败: ${state.backendError}');
                  } catch (e) {
                    _toast('$e');
                  }
                },
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('保存并连接'),
              ),
            ],
          ),

          // —— 大模型 ——
          _section(
            icon: Icons.smart_toy_outlined,
            accent: const Color(0xFFA78BFA),
            title: '大模型',
            subtitle: 'OpenAI 兼容网关 · 思考级别',
            children: [
              TextField(
                controller: llmBase,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  labelText: 'LLM Base URL',
                  helperText: '需含 /v1，例如 http://host:port/v1',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: llmKey,
                obscureText: _obscureKey,
                enableSuggestions: false,
                autocorrect: false,
                style: const TextStyle(fontSize: 13.5, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: 'API Key',
                  helperText: '本地明文保存',
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: _obscureKey ? '显示' : '隐藏',
                    icon: Icon(_obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _modelIds.isEmpty
                        ? TextField(
                            controller: llmModel,
                            style: const TextStyle(fontSize: 13.5),
                            decoration: const InputDecoration(
                              labelText: '模型',
                              helperText: '可点右侧刷新拉取列表',
                              isDense: true,
                            ),
                          )
                        : DropdownButtonFormField<String>(
                            value: _modelIds.contains(llmModel.text) ? llmModel.text : null,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: '模型', isDense: true),
                            items: [
                              for (final id in _modelIds)
                                DropdownMenuItem(
                                  value: id,
                                  child: Text(id, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                                ),
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
                        : const Icon(Icons.refresh, size: 20),
                  ),
                ],
              ),
              if (_modelIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: Text('共 ${_modelIds.length} 个模型', style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E))),
                ),
              DropdownButtonFormField<String>(
                value: const ['none', 'auto', 'low', 'medium', 'high', 'xhigh'].contains(thinkingLevel)
                    ? thinkingLevel
                    : 'auto',
                decoration: const InputDecoration(
                  labelText: '思考级别',
                  helperText: 'none 关闭 · auto 开启 · low→xhigh 强度',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('none · 关闭思考')),
                  DropdownMenuItem(value: 'auto', child: Text('auto · 开启（默认）')),
                  DropdownMenuItem(value: 'low', child: Text('low')),
                  DropdownMenuItem(value: 'medium', child: Text('medium')),
                  DropdownMenuItem(value: 'high', child: Text('high')),
                  DropdownMenuItem(value: 'xhigh', child: Text('xhigh')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => thinkingLevel = v);
                },
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: !state.backendOk
                    ? null
                    : () async {
                        try {
                          await state.saveLlm(
                            baseUrl: llmBase.text.trim(),
                            model: llmModel.text.trim(),
                            apiKey: llmKey.text,
                            thinkingLevel: thinkingLevel,
                          );
                          await _refreshModels(state);
                          _toast('LLM 已保存');
                        } catch (e) {
                          _toast('$e');
                        }
                      },
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('保存 LLM'),
              ),
            ],
          ),

          // —— 显示 / 字体 ——
          _section(
            icon: Icons.text_fields,
            accent: const Color(0xFF79C0FF),
            title: '显示与字体',
            subtitle: '分别调整终端 / Agent / 记录',
            children: [
              _fontSlider(
                label: '终端字号',
                value: state.termFontSize,
                min: 10,
                max: 20,
                onChanged: (v) => state.setTermFontSize(v),
                hint: '终端页也可用 A+ / A−',
              ),
              const SizedBox(height: 6),
              _fontSlider(
                label: 'Agent 正文字号',
                value: state.agentFontSize,
                min: 12,
                max: 20,
                onChanged: (v) => state.setAgentFontSize(v),
                hint: '影响助手、用户气泡、工具/思考块',
              ),
              const SizedBox(height: 6),
              _fontSlider(
                label: '记录字号',
                value: state.recordsFontSize,
                min: 11,
                max: 18,
                onChanged: (v) => state.setRecordsFontSize(v),
                hint: '审计列表与详情',
              ),
              const SizedBox(height: 8),
              // live preview chips
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('预览 · Agent', style: TextStyle(fontSize: state.agentFontSize, color: const Color(0xFFE6EDF3))),
                    const SizedBox(height: 4),
                    Text(
                      '预览 · 记录  exit 0 · 命令示例',
                      style: TextStyle(
                        fontSize: state.recordsFontSize,
                        fontFamily: 'monospace',
                        color: const Color(0xFF8B949E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$ preview · terminal',
                      style: TextStyle(
                        fontSize: state.termFontSize,
                        fontFamily: 'monospace',
                        color: const Color(0xFF3FB950),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // —— Agent 行为 ——
          _section(
            icon: Icons.rule_folder_outlined,
            accent: const Color(0xFFD29922),
            title: 'Agent 行为',
            subtitle: '确认策略与安全',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('写操作需确认', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text('开启后，写/破坏类命令需点运行', style: TextStyle(fontSize: 11.5)),
                value: state.confirmWrites,
                onChanged: (v) => state.setConfirmWrites(v),
              ),
            ],
          ),

          // —— 连通性 ——
          _section(
            icon: Icons.network_check,
            accent: const Color(0xFF39D353),
            title: '连通性检测',
            subtitle: '测当前主机 SSH 与模型可达',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: !state.backendOk || state.selectedHostId == null || pinging
                        ? null
                        : () async {
                            setState(() {
                              pinging = true;
                              pingMsg = null;
                            });
                            try {
                              final o = await state.testHostSsh();
                              setState(() => pingMsg = 'SSH OK: $o');
                            } catch (e) {
                              setState(() => pingMsg = 'SSH 失败: $e');
                            } finally {
                              setState(() => pinging = false);
                            }
                          },
                    icon: const Icon(Icons.terminal, size: 16),
                    label: const Text('测 SSH'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: !state.backendOk || state.selectedHostId == null || pinging
                        ? null
                        : () async {
                            setState(() {
                              pinging = true;
                              pingMsg = null;
                            });
                            try {
                              final o = await state.testLlmReachable();
                              setState(() => pingMsg = o);
                            } catch (e) {
                              setState(() => pingMsg = '模型失败: $e');
                            } finally {
                              setState(() => pinging = false);
                            }
                          },
                    icon: const Icon(Icons.psychology_outlined, size: 16),
                    label: const Text('测模型'),
                  ),
                  if (pinging)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                ],
              ),
              if (state.selectedHostId == null)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('请先在「主机」页选中一台主机', style: TextStyle(fontSize: 11, color: Color(0xFFD29922))),
                ),
              if (pingMsg != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: SelectableText(
                    pingMsg!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Color(0xFFC9D1D9)),
                  ),
                ),
              ],
            ],
          ),

          // —— 保活 ——
          _section(
            icon: Icons.battery_charging_full,
            accent: const Color(0xFF3FB950),
            title: '后台保活',
            subtitle: '忽略电池优化，降低被系统杀掉概率',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('忽略电池优化', style: TextStyle(fontSize: 13.5)),
                subtitle: Text(
                  state.batteryIgnored ? '已忽略（有利于后台）' : '未忽略，后台易被杀',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: state.batteryIgnored ? const Color(0xFF3FB950) : const Color(0xFFD29922),
                  ),
                ),
                trailing: FilledButton.tonal(
                  onPressed: () async {
                    await state.requestBatteryExempt();
                    _toast(state.batteryIgnored ? '已忽略' : '请在系统页确认');
                  },
                  child: const Text('去设置'),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => state.openBatterySettings(),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('打开系统电池优化列表'),
                ),
              ),
            ],
          ),

          // —— 数据与诊断 ——
          _section(
            icon: Icons.medical_services_outlined,
            accent: const Color(0xFFF778BA),
            title: '数据与诊断',
            subtitle: '导入导出 · 日志 · HostKey',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: !state.backendOk
                        ? null
                        : () async {
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
                                    TextButton(
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: json));
                                        Navigator.pop(c);
                                        _toast('已复制');
                                      },
                                      child: const Text('复制'),
                                    ),
                                    TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
                                  ],
                                ),
                              );
                            } catch (e) {
                              _toast('$e');
                            }
                          },
                    icon: const Icon(Icons.upload_outlined, size: 16),
                    label: const Text('导出配置'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: !state.backendOk
                        ? null
                        : () async {
                            final ctrl = TextEditingController();
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('导入配置 JSON'),
                                content: TextField(
                                  controller: ctrl,
                                  maxLines: 12,
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                                ),
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
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('导入配置'),
                  ),
                  FilledButton.tonalIcon(
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
                              child: SelectableText(
                                log.isEmpty ? '(empty)' : log,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                              ),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: log));
                                Navigator.pop(c);
                              },
                              child: const Text('复制关闭'),
                            ),
                            TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.article_outlined, size: 16),
                    label: const Text('后端日志'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: !state.backendOk
                        ? null
                        : () async {
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
                    icon: const Icon(Icons.vpn_key_outlined, size: 16),
                    label: const Text('HostKey'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
