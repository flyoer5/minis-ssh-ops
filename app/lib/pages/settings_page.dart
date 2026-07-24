import 'package:flutter/material.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
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


  Future<void> _openHostKeySheet(AppState state) async {
    try {
      final r = await state.api.listKnownHosts();
      var entries = List<Map>.from(((r['entries'] as List?) ?? []).whereType<Map>());
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        builder: (c) {
          return StatefulBuilder(
            builder: (c, setLocal) {
              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.62,
                maxChildSize: 0.92,
                minChildSize: 0.4,
                builder: (_, sc) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('HostKey（TOFU）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                SizedBox(height: 4),
                                Text(
                                  '首次连接自动信任并记住指纹；重装系统后若指纹变化需删除旧记录再连。',
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
                                ),
                              ],
                            ),
                          ),
                          IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Row(
                        children: [
                          Text('${entries.length} 条信任记录', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          const Spacer(),
                          if (entries.isNotEmpty)
                            TextButton(
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: c,
                                  builder: (d) => AlertDialog(
                                    title: const Text('清空全部 HostKey？'),
                                    content: const Text('下次连接所有主机都会重新弹出信任流程。'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
                                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('清空')),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                final res = await state.api.clearKnownHosts();
                                final n = res['deleted'];
                                setLocal(() => entries = []);
                                if (mounted) _toast('已清空 $n 条');
                              },
                              child: const Text('全部清空', style: TextStyle(color: AppColors.danger)),
                            ),
                          IconButton(
                            tooltip: '刷新',
                            onPressed: () async {
                              final r2 = await state.api.listKnownHosts();
                              setLocal(() {
                                entries = List<Map>.from(((r2['entries'] as List?) ?? []).whereType<Map>());
                              });
                            },
                            icon: const Icon(Icons.refresh, size: 20),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    Expanded(
                      child: entries.isEmpty
                          ? const Center(child: Text('暂无信任记录', style: TextStyle(color: AppColors.textMuted)))
                          : ListView.separated(
                              controller: sc,
                              itemCount: entries.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.surface2),
                              itemBuilder: (_, i) {
                                final e = entries[i];
                                final host = e['host']?.toString() ?? '';
                                final port = e['port'] is int ? e['port'] as int : int.tryParse('${e['port']}') ?? 22;
                                final fp = e['fingerprint']?.toString() ?? '';
                                final kt = e['keyType']?.toString() ?? '';
                                return ListTile(
                                  dense: true,
                                  title: Text('$host:$port', style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                    [
                                      if (kt.isNotEmpty) kt,
                                      if (fp.isNotEmpty) 'SHA256:$fp',
                                    ].join(' · '),
                                    maxLines: 3,
                                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textMuted),
                                  ),
                                  trailing: IconButton(
                                    tooltip: '删除并重新信任',
                                    icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
                                    onPressed: () async {
                                      final ok = await showDialog<bool>(
                                        context: c,
                                        builder: (d) => AlertDialog(
                                          title: Text('删除 $host:$port？'),
                                          content: const Text('下次连接该主机将按首次连接重新记录指纹。'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
                                            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('删除')),
                                          ],
                                        ),
                                      );
                                      if (ok != true) return;
                                      await state.api.deleteKnownHost(host, port);
                                      setLocal(() {
                                        entries = entries.where((x) {
                                          final h = x['host']?.toString() ?? '';
                                          final p = x['port'] is int ? x['port'] as int : int.tryParse('${x['port']}') ?? 22;
                                          return !(h == host && p == port);
                                        }).toList();
                                      });
                                      if (mounted) _toast('已删除 $host:$port');
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _openLongMemSheet(AppState state) async {
    try {
      final r = await state.api.listSessionMemory();
      var entries = List<Map>.from(((r['entries'] as List?) ?? []).whereType<Map>());
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        builder: (c) {
          return StatefulBuilder(
            builder: (c, setLocal) {
              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.65,
                maxChildSize: 0.94,
                minChildSize: 0.4,
                builder: (_, sc) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Agent 长期记忆', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                SizedBox(height: 4),
                                Text(
                                  '会话变长后会把旧轮次折叠成 summary/facts，供后续对话引用。可按会话查看或清空。',
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
                                ),
                              ],
                            ),
                          ),
                          IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Row(
                        children: [
                          Text('${entries.length} 条', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          const Spacer(),
                          if (entries.isNotEmpty)
                            TextButton(
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: c,
                                  builder: (d) => AlertDialog(
                                    title: const Text('清空全部长期记忆？'),
                                    content: const Text('不会删除聊天记录，只清 summary/facts。'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
                                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('清空')),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                final res = await state.api.deleteSessionMemory(all: true);
                                setLocal(() => entries = []);
                                if (mounted) _toast('已清空 ${res['deleted'] ?? ''} 条记忆');
                              },
                              child: const Text('全部清空', style: TextStyle(color: AppColors.danger)),
                            ),
                          IconButton(
                            tooltip: '刷新',
                            onPressed: () async {
                              final r2 = await state.api.listSessionMemory();
                              setLocal(() {
                                entries = List<Map>.from(((r2['entries'] as List?) ?? []).whereType<Map>());
                              });
                            },
                            icon: const Icon(Icons.refresh, size: 20),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    Expanded(
                      child: entries.isEmpty
                          ? const Center(child: Text('暂无长期记忆', style: TextStyle(color: AppColors.textMuted)))
                          : ListView.separated(
                              controller: sc,
                              padding: const EdgeInsets.only(bottom: 16),
                              itemCount: entries.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.surface2),
                              itemBuilder: (_, i) {
                                final e = entries[i];
                                final sid = e['sessionId']?.toString() ?? '';
                                final sum = e['summary']?.toString() ?? '';
                                final facts = e['facts']?.toString() ?? '';
                                final updated = e['updatedAt']?.toString() ?? '';
                                final shortId = sid.length > 12 ? '${sid.substring(0, 12)}…' : sid;
                                return ListTile(
                                  isThreeLine: true,
                                  title: Text(shortId, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                    [
                                      if (updated.isNotEmpty) updated,
                                      if (sum.isNotEmpty) sum,
                                      if (facts.isNotEmpty) facts,
                                    ].where((s) => s.trim().isNotEmpty).join('\n'),
                                    maxLines: 5,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.3),
                                  ),
                                  trailing: IconButton(
                                    tooltip: '删除',
                                    icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
                                    onPressed: () async {
                                      final ok = await showDialog<bool>(
                                        context: c,
                                        builder: (d) => AlertDialog(
                                          title: const Text('删除此会话记忆？'),
                                          content: Text(shortId, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
                                            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('删除')),
                                          ],
                                        ),
                                      );
                                      if (ok != true) return;
                                      await state.api.deleteSessionMemory(sessionId: sid);
                                      setLocal(() {
                                        entries = entries.where((x) => x['sessionId']?.toString() != sid).toList();
                                      });
                                      if (mounted) _toast('已删除记忆');
                                    },
                                  ),
                                  onTap: () {
                                    showDialog(
                                      context: c,
                                      builder: (d) => AlertDialog(
                                        title: Text(shortId, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                                        content: SizedBox(
                                          width: double.maxFinite,
                                          child: SingleChildScrollView(
                                            child: SelectableText(
                                              [
                                                if (updated.isNotEmpty) '更新: $updated',
                                                if (sum.isNotEmpty) 'SUMMARY:\n$sum',
                                                if (facts.isNotEmpty) 'FACTS:\n$facts',
                                              ].join('\n\n'),
                                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35),
                                            ),
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () {
                                              Clipboard.setData(ClipboardData(text: 'SUMMARY:\n$sum\n\nFACTS:\n$facts'));
                                              Navigator.pop(d);
                                            },
                                            child: const Text('复制'),
                                          ),
                                          TextButton(onPressed: () => Navigator.pop(d), child: const Text('关闭')),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      _toast('$e');
    }
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
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
                        Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.25)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.surface2),
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
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                value.toStringAsFixed(0),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.chipBlue),
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
          Text(hint, style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
      ],
    );
  }

  Widget _portChip(String baseUrl) {
    var label = '端口 ?';
    try {
      final u = Uri.tryParse(baseUrl);
      if (u != null && u.hasPort) {
        label = '端口 ${u.port}';
      } else if (u != null && u.host.isNotEmpty) {
        label = u.scheme == 'https' ? '端口 443' : '端口 80';
      }
    } catch (_) {}
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentDeep.withAlpha(0x22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.accentDeep.withAlpha(0x55)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.chipBlue)),
    );
  }

  Widget _statusChip(bool ok, String text) {
    final c = ok ? AppColors.success : AppColors.danger;
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
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        toolbarHeight: 44,
        backgroundColor: AppColors.bg,
        titleSpacing: 12,
        title: const Text('设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
        children: [
          // —— 关于 ——
          _section(
            icon: Icons.info_outline,
            accent: AppColors.accentSoft,
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
                      color: AppColors.accentDeep.withAlpha(0x33),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('1.4.9', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.chipBlue)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '主机探针 · Agent · 终端 · SFTP · 审计',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),

          // —— 后端 ——
          _section(
            icon: Icons.dns_outlined,
            accent: AppColors.success,
            title: '后端连接',
            subtitle: '本机 Go 服务地址与 Local Token',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _statusChip(state.backendOk, state.backendOk ? '已连接' : '未连接'),
                  _portChip(state.api.baseUrl),
                  Text(
                    state.api.baseUrl,
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '本地后端端口按 applicationId 派生（17890+hash%1024），避免与其它安装包抢同一端口。',
                style: TextStyle(fontSize: 11, color: AppColors.textFaint, height: 1.35),
              ),
              if (state.backendNote != null) ...[
                const SizedBox(height: 6),
                Text(state.backendNote!, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
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
            accent: AppColors.purple,
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
                  child: Text('共 ${_modelIds.length} 个模型', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
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
            accent: AppColors.chipBlue,
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
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('预览 · Agent', style: TextStyle(fontSize: state.agentFontSize, color: AppColors.text)),
                    const SizedBox(height: 4),
                    Text(
                      '预览 · 记录  exit 0 · 命令示例',
                      style: TextStyle(
                        fontSize: state.recordsFontSize,
                        fontFamily: 'monospace',
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$ preview · terminal',
                      style: TextStyle(
                        fontSize: state.termFontSize,
                        fontFamily: 'monospace',
                        color: AppColors.success,
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
            accent: AppColors.warning,
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
                  child: Text('请先在「主机」页选中一台主机', style: TextStyle(fontSize: 11, color: AppColors.warning)),
                ),
              if (pingMsg != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SelectableText(
                    pingMsg!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: AppColors.textCode),
                  ),
                ),
              ],
            ],
          ),

          // —— 保活 ——
          _section(
            icon: Icons.battery_charging_full,
            accent: AppColors.success,
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
                    color: state.batteryIgnored ? AppColors.success : AppColors.warning,
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
            subtitle: '导入导出 · 日志 · HostKey · 长期记忆',
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
                    onPressed: !state.backendOk ? null : () => _openHostKeySheet(state),
                    icon: const Icon(Icons.vpn_key_outlined, size: 16),
                    label: const Text('HostKey'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: !state.backendOk ? null : () => _openLongMemSheet(state),
                    icon: const Icon(Icons.psychology_outlined, size: 16),
                    label: const Text('长期记忆'),
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
