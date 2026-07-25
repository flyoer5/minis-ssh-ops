import 'package:flutter/material.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:ssh_ai_agent/widgets/nav_menu.dart';

part 'settings_widgets.dart';

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
  final customPrompt = TextEditingController();
  String thinkingLevel = 'auto';
  bool loaded = false;
  String? pingMsg;
  bool pinging = false;
  List<String> _modelIds = [];
  bool _loadingModels = false;
  bool _obscureKey = true;

  // Local slider drafts — write SharedPreferences only onChangeEnd (avoids lag).
  double? _draftMaxRounds;
  double? _draftTemp;
  double? _draftProbeConc;
  double? _draftAutoProbe;
  double? _draftTermFont;
  double? _draftAgentFont;
  double? _draftRecordsFont;
  double? _draftUiFont;
  double? _draftEditorFont;

  @override
  // Settings is rarely sticky; free memory when off-tab.
  bool get wantKeepAlive => false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loaded) return;
    loaded = true;
    final s = context.read<AppState>();
    baseUrl.text = s.api.baseUrl;
    token.text = s.api.localToken;
    customPrompt.text = s.agentCustomPrompt;
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
    customPrompt.dispose();
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
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 28),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified_user_outlined, size: 36, color: AppColors.textFaint),
                                    SizedBox(height: 10),
                                    Text('暂无信任主机密钥', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                                    SizedBox(height: 6),
                                    Text(
                                      '首次连接新主机会提示 TOFU 信任指纹，确认后出现在这里。',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 12, color: AppColors.textFaint, height: 1.35),
                                    ),
                                  ],
                                ),
                              ),
                            )
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
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 28),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.psychology_outlined, size: 36, color: AppColors.textFaint),
                                    SizedBox(height: 10),
                                    Text('暂无长期记忆', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                                    SizedBox(height: 6),
                                    Text(
                                      'Agent 在会话中沉淀的摘要与事实会列在此处，便于跨会话复用。',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 12, color: AppColors.textFaint, height: 1.35),
                                    ),
                                  ],
                                ),
                              ),
                            )
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

  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: NavMenuButton.leadingOf(context),
        leadingWidth: NavMenuButton.leadingWidthOf(context),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('机枢', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text('SSH 运维 Agent · 主机枢纽', style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accentDeep.withAlpha(0x33),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      state.backendVersion?.isNotEmpty == true ? state.backendVersion! : '1.5.2',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.chipBlue),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'SSH 运维 Agent · 主机枢纽',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
              ),
              if (state.backendFeatures.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in state.backendFeatures)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          f,
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace'),
                        ),
                      ),
                  ],
                ),
              ],
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
              if (state.backendVersion != null) ...[
                const SizedBox(height: 6),
                Text('后端版本 ${state.backendVersion}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace')),
              ],
              if (state.backendFeatures.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('能力', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in state.backendFeatures)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: f == 'tokstream' || f == 'stream' || f == 'fscopy' || f == 'fsmove'
                                ? AppColors.accentSoft.withAlpha(0x66)
                                : AppColors.border,
                          ),
                        ),
                        child: Text(
                          f,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            color: f == 'tokstream' || f == 'stream' ? AppColors.accentSoft : AppColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
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
                  helperText: '关闭 · 自动 · 低→极高（影响推理强度与延迟）',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('关闭思考')),
                  DropdownMenuItem(value: 'auto', child: Text('自动（默认）')),
                  DropdownMenuItem(value: 'low', child: Text('低')),
                  DropdownMenuItem(value: 'medium', child: Text('中')),
                  DropdownMenuItem(value: 'high', child: Text('高')),
                  DropdownMenuItem(value: 'xhigh', child: Text('极高')),
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
            subtitle: '导航 / 终端 / Agent / 记录 / 列表 / 编辑器',
            children: [
              const Text('导航方式', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'bottom', label: Text('底部栏'), icon: Icon(Icons.space_dashboard_outlined, size: 16)),
                  ButtonSegment(value: 'menu', label: Text('左上角菜单'), icon: Icon(Icons.menu, size: 16)),
                ],
                selected: {state.navMode},
                onSelectionChanged: (s) {
                  if (s.isEmpty) return;
                  state.setNavMode(s.first);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(const TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                state.navIsMenu ? '点左上角 ☰ 切换页面，内容区更高' : '底部六项导航（高度 56）',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('主机卡片精简', style: TextStyle(fontSize: 13.5)),
                subtitle: Text(
                  state.hostCardCompact ? '仅内存 + 硬盘' : 'CPU + 内存 + 硬盘 + 运行时间',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
                value: state.hostCardCompact,
                onChanged: (v) => state.setHostCardCompact(v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('流式 Markdown', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text(
                  '关闭则流式过程以纯文本暂示，完成后再渲染 Markdown（更稳）',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
                value: state.streamMarkdown,
                onChanged: (v) => state.setStreamMarkdown(v),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Expanded(
                    child: Text('探针并发', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                  Text(
                    '${(_draftProbeConc ?? state.probeConcurrency.toDouble()).round()}',
                    style: const TextStyle(fontFamily: 'monospace', color: AppColors.chipBlue),
                  ),
                ],
              ),
              Slider(
                value: (_draftProbeConc ?? state.probeConcurrency.toDouble()).clamp(1, 6),
                min: 1,
                max: 6,
                divisions: 5,
                label: '${(_draftProbeConc ?? state.probeConcurrency.toDouble()).round()}',
                onChanged: (v) => setState(() => _draftProbeConc = v),
                onChangeEnd: (v) {
                  state.setProbeConcurrency(v.round());
                  setState(() => _draftProbeConc = null);
                },
              ),
              const Text(
                '刷新主机列表时同时探测的 SSH 数（1–6）',
                style: TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Text('自动探针间隔', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                  Text(
                    (() { final n = (_draftAutoProbe ?? state.hostAutoProbeSec.toDouble()).round(); return n == 0 ? '关' : '${n}s'; })(),
                    style: const TextStyle(fontFamily: 'monospace', color: AppColors.chipBlue),
                  ),
                ],
              ),
              Slider(
                value: (_draftAutoProbe ?? state.hostAutoProbeSec.toDouble()).clamp(0, 300),
                min: 0,
                max: 300,
                divisions: 30,
                label: (() {
                  final n = (_draftAutoProbe ?? state.hostAutoProbeSec.toDouble()).round();
                  return n == 0 ? '关' : '${n}s';
                })(),
                onChanged: (v) => setState(() => _draftAutoProbe = v),
                onChangeEnd: (v) {
                  final raw = v.round();
                  final snapped = raw == 0 ? 0 : ((raw / 10).round() * 10).clamp(10, 300);
                  state.setHostAutoProbeSec(snapped);
                  setState(() => _draftAutoProbe = null);
                },
              ),
              const Text(
                '后台自动刷新探针（0=关闭）。频繁探针会增加 SSH 连接和电量开销。',
                style: TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
              const SizedBox(height: 8),
              _fontSlider(
                context: context,
                label: '终端字号',
                value: _draftTermFont ?? state.termFontSize,
                min: 10,
                max: 20,
                onChanged: (v) => setState(() => _draftTermFont = v),
                onChangeEnd: (v) { state.setTermFontSize(v); setState(() => _draftTermFont = null); },
                hint: '终端页也可用 A+ / A−',
              ),
              const SizedBox(height: 6),
              _fontSlider(
                context: context,
                label: 'Agent 正文字号',
                value: _draftAgentFont ?? state.agentFontSize,
                min: 12,
                max: 20,
                onChanged: (v) => setState(() => _draftAgentFont = v),
                onChangeEnd: (v) { state.setAgentFontSize(v); setState(() => _draftAgentFont = null); },
                hint: '影响助手、用户气泡、工具/思考块',
              ),
              const SizedBox(height: 6),
              _fontSlider(
                context: context,
                label: '记录字号',
                value: _draftRecordsFont ?? state.recordsFontSize,
                min: 11,
                max: 18,
                onChanged: (v) => setState(() => _draftRecordsFont = v),
                onChangeEnd: (v) { state.setRecordsFontSize(v); setState(() => _draftRecordsFont = null); },
                hint: '审计列表与详情',
              ),
              const SizedBox(height: 6),
              _fontSlider(
                context: context,
                label: '界面列表字号',
                value: _draftUiFont ?? state.uiFontSize,
                min: 11,
                max: 20,
                onChanged: (v) => setState(() => _draftUiFont = v),
                onChangeEnd: (v) { state.setUiFontSize(v); setState(() => _draftUiFont = null); },
                hint: '主机卡片、文件列表等',
              ),
              const SizedBox(height: 6),
              _fontSlider(
                context: context,
                label: '编辑器默认字号',
                value: _draftEditorFont ?? state.editorFontSize,
                min: 10,
                max: 24,
                onChanged: (v) => setState(() => _draftEditorFont = v),
                onChangeEnd: (v) { state.setEditorFontSize(v); setState(() => _draftEditorFont = null); },
                hint: '远程文件编辑器打开时的默认大小',
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
                      '主机 · 文件列表  root@vps',
                      style: TextStyle(fontSize: state.uiFontSize, color: AppColors.textCode),
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
                    const SizedBox(height: 4),
                    Text(
                      'editor · main.go',
                      style: TextStyle(
                        fontSize: state.editorFontSize,
                        fontFamily: 'monospace',
                        color: AppColors.chipBlue,
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
            subtitle: '温度 · 轮数 · 提示词 · 输入体验',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('写操作需确认', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text(
                  '开启：写/破坏类命令弹出确认卡，点「运行并继续」后执行并让 Agent 接着干；关闭：自动执行（仍拦截策略黑名单）',
                  style: TextStyle(fontSize: 11.5),
                ),
                value: state.confirmWrites,
                onChanged: (v) => state.setConfirmWrites(v),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Expanded(
                    child: Text('工具循环轮数', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      '${(_draftMaxRounds ?? state.agentMaxRounds.toDouble()).round()}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppColors.chipBlue, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              Slider(
                value: (_draftMaxRounds ?? state.agentMaxRounds.toDouble()).clamp(1, 99),
                min: 1,
                max: 99,
                divisions: 98,
                label: '${(_draftMaxRounds ?? state.agentMaxRounds.toDouble()).round()}',
                onChanged: (v) => setState(() => _draftMaxRounds = v),
                onChangeEnd: (v) {
                  state.setAgentMaxRounds(v.round());
                  setState(() => _draftMaxRounds = null);
                },
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in const [4, 8, 12, 24, 40, 64])
                    ActionChip(
                      label: Text('$n', style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: state.agentMaxRounds == n ? AppColors.accentDeep.withAlpha(0x33) : null,
                      onPressed: () => state.setAgentMaxRounds(n),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '每次提问最多调几轮工具（1–99，默认 12）。步骤越多耗时越长。',
                style: TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Expanded(
                    child: Text('模型温度', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                  Text(
                    (() {
                      final x = _draftTemp ?? state.agentTemperature;
                      return x == 0 ? '默认' : x.toStringAsFixed(1);
                    })(),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppColors.chipBlue, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              Slider(
                value: (_draftTemp ?? state.agentTemperature).clamp(0, 2),
                min: 0,
                max: 2,
                divisions: 20,
                label: (() {
                  final x = _draftTemp ?? state.agentTemperature;
                  return x == 0 ? '默认' : x.toStringAsFixed(1);
                })(),
                onChanged: (v) => setState(() => _draftTemp = v),
                onChangeEnd: (v) {
                  state.setAgentTemperature(v);
                  setState(() => _draftTemp = null);
                },
              ),
              const Text('0=默认 0.2，越高越随机。适合创意任务调高。', style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
              const SizedBox(height: 8),
              const Text('自定义提示词', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(
                controller: customPrompt,
                decoration: const InputDecoration(
                  hintText: '追加到系统提示词末尾（如：优先使用 Docker）',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                minLines: 1,
                style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                onChanged: (v) => state.setAgentCustomPrompt(v),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('显示思考过程', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text('关闭后不显示推理过程气泡，视觉更紧凑', style: TextStyle(fontSize: 11.5)),
                value: state.agentShowReasoning,
                onChanged: (v) => state.setAgentShowReasoning(v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('折叠成功工具卡', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text('成功工具卡折叠只保留标题；失败仍自动展开', style: TextStyle(fontSize: 11.5)),
                value: state.agentCollapseTools,
                onChanged: (v) => state.setAgentCollapseTools(v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('流式跟随底部', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text('流式输出时底部自动跟随，手动上滑暂停跟随', style: TextStyle(fontSize: 11.5)),
                value: state.agentAutoScroll,
                onChanged: (v) => state.setAgentAutoScroll(v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('回车发送', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text('关闭则回车换行，需点发送按钮', style: TextStyle(fontSize: 11.5)),
                value: state.agentEnterToSend,
                onChanged: (v) => state.setAgentEnterToSend(v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('发送后保持键盘', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text('发送后不收起键盘，一条接一条问', style: TextStyle(fontSize: 11.5)),
                value: state.agentKeepKeyboard,
                onChanged: (v) => state.setAgentKeepKeyboard(v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('触感反馈', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text('发送时轻微震动', style: TextStyle(fontSize: 11.5)),
                value: state.hapticFeedback,
                onChanged: (v) => state.setHapticFeedback(v),
              ),
            ],
          ),

          // —— 连通性 ——
          _section(
            icon: Icons.network_check,
            accent: AppColors.accentMint,
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
            accent: AppColors.accentPink,
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
