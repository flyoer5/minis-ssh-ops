import 'package:flutter/material.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:ssh_ai_agent/widgets/nav_menu.dart';
import 'package:ssh_ai_agent/util/feedback.dart';

part 'settings_widgets.dart';
part 'settings_sheets.dart';
part 'settings_sections.dart';
part 'settings_hostkey_sheet.dart';
part 'settings_longmem_sheet.dart';
part 'settings_backend_section.dart';
part 'settings_llm_section.dart';
part 'settings_display_section.dart';
part 'settings_behavior_section.dart';
part 'settings_connectivity_section.dart';
part 'settings_battery_section.dart';
part 'settings_data_section.dart';
part 'settings_about_section.dart';

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
  final _searchCtrl = TextEditingController();
  String _settingsQuery = '';
  String thinkingLevel = 'auto';
  bool loaded = false;
  String? pingMsg;
  bool pinging = false;
  List<String> _modelIds = [];
  bool _loadingModels = false;
  bool _obscureKey = true;

  // Local slider drafts: write SharedPreferences only onChangeEnd to avoid lag.
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
    if (s.backendOk && llmBase.text.trim().isNotEmpty) {
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
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshModels(
    AppState state, {
    bool notifyIfUnconfigured = false,
    bool notifyOnError = true,
  }) async {
    if (!state.backendOk || _loadingModels) return;
    if (llmBase.text.trim().isEmpty) {
      if (notifyIfUnconfigured) {
        _toast('尚未配置 LLM 服务地址，请先填写并保存。');
      }
      return;
    }
    setState(() => _loadingModels = true);
    try {
      final ids = await state.fetchModels();
      if (!mounted) return;
      setState(() {
        _modelIds = ids;
        if (llmModel.text.isEmpty && ids.isNotEmpty) llmModel.text = ids.first;
      });
    } catch (e) {
      if (!mounted || !notifyOnError) return;
      final message = cleanError(e);
      if (message.contains('configure LLM baseUrl first')) {
        _toast('尚未配置 LLM 服务地址，请先填写并保存。');
      } else {
        _toast('拉取模型列表失败：$message');
      }
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  void _toast(String m) => showSnack(context, m, floating: true);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    context.select((AppState s) => s.backendOk);
    context.select((AppState s) => s.backendVersion);
    context.select((AppState s) => s.backendFeatures.length);
    context.select((AppState s) => s.llm);
    context.select((AppState s) => s.agentMaxRounds);
    context.select((AppState s) => s.agentTemperature);
    context.select((AppState s) => s.agentCustomPrompt);
    context.select((AppState s) => s.confirmWrites);
    context.select((AppState s) => s.agentShowReasoning);
    context.select((AppState s) => s.agentCollapseTools);
    context.select((AppState s) => s.agentAutoScroll);
    context.select((AppState s) => s.agentEnterToSend);
    context.select((AppState s) => s.agentKeepKeyboard);
    context.select((AppState s) => s.hapticFeedback);
    context.select((AppState s) => s.streamMarkdown);
    context.select((AppState s) => s.probeConcurrency);
    context.select((AppState s) => s.hostAutoProbeSec);
    context.select((AppState s) => s.termFontSize);
    context.select((AppState s) => s.agentFontSize);
    context.select((AppState s) => s.recordsFontSize);
    context.select((AppState s) => s.uiFontSize);
    context.select((AppState s) => s.editorFontSize);
    context.select((AppState s) => s.hostCardCompact);
    context.select((AppState s) => s.navIsMenu);
    final state = context.read<AppState>();
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: NavMenuButton.leadingOf(context),
        leadingWidth: NavMenuButton.leadingWidthOf(context),
        toolbarHeight: 48,
        backgroundColor: AppColors.bg,
        titleSpacing: 12,
        title: const Text('设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _settingsQuery = v.trim().toLowerCase()),
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索设置项（如：主题、字体、确认、日志）',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _settingsQuery.isEmpty
                  ? null
                  : IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _settingsQuery = '');
                      },
                    ),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.accentSoft),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ..._buildSettingsSections(state),
        ],
      ),
    );
  }
}
