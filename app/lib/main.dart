import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/pages/agent_page.dart';
import 'package:ssh_ai_agent/pages/files_page.dart';
import 'package:ssh_ai_agent/pages/hosts_page.dart';
import 'package:ssh_ai_agent/pages/records_page.dart';
import 'package:ssh_ai_agent/pages/settings_page.dart';
import 'package:ssh_ai_agent/pages/terminal_page.dart';
import 'package:ssh_ai_agent/state/app_state.dart';
import 'package:ssh_ai_agent/theme/app_theme.dart';
import 'package:ssh_ai_agent/util/feedback.dart';
import 'package:ssh_ai_agent/widgets/ime_inset.dart';
import 'package:ssh_ai_agent/widgets/nav_menu.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return _AppErrorSurface(details: details);
  };
  runApp(const SshAiAgentApp());
}

class _AppErrorSurface extends StatelessWidget {
  const _AppErrorSurface({required this.details});
  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final msg = details.exceptionAsString();
    final isDark = context.isDark;
    return Material(
      color: isDark ? AppColors.bg : const Color(0xFFF6F8FA),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Icon(Icons.error_outline, size: 48, color: isDark ? AppColors.danger : const Color(0xFFD1242F)),
              const SizedBox(height: 12),
              Text(
                '界面出错了',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: isDark ? AppColors.text : const Color(0xFF1F2328)),
              ),
              const SizedBox(height: 8),
              Text(
                '通常是某次操作触发了异常。可返回继续用；若反复出现请到设置导出日志。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: isDark ? AppColors.textMuted : const Color(0xFF59636E), height: 1.4),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surface : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isDark ? AppColors.border : const Color(0xFFD1D9E0)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      msg,
                      style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: isDark ? AppColors.dangerSoft : const Color(0xFFFF8182)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: msg));
                        showSnack(context, '错误信息已复制');
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('复制错误'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        final nav = Navigator.maybeOf(context);
                        if (nav != null && nav.canPop()) {
                          nav.pop();
                        }
                      },
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('关闭此页'),
                    ),
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

class SshAiAgentApp extends StatelessWidget {
  const SshAiAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(ApiClient())..bootstrap(),
      child: Consumer<AppState>(
        builder: (context, appState, _) {
          final themeMode = switch (appState.themeMode) {
            'dark' => ThemeMode.dark,
            'light' => ThemeMode.light,
            _ => ThemeMode.system,
          };
          return MaterialApp(
            title: '机枢',
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildAppTheme(dark: false),
            darkTheme: buildAppTheme(dark: true),
            themeMode: themeMode,
            builder: (context, child) {
              ErrorWidget.builder = (FlutterErrorDetails details) {
                return _AppErrorSurface(details: details);
              };
              return child ?? const SizedBox.shrink();
            },
            home: const RootGate(),
          );
        },
      ),
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final ready = context.select((AppState s) => s.bootstrapped);
    if (!ready) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: 14),
              Text('启动中…', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      );
    }
    return const HomeShell();
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  void _selectTab(int next) {
    if (!mounted || next == index) return;
    setState(() => index = next);
  }

  final _pages = const <Widget>[
    HostsPage(),
    AgentPage(),
    TerminalPage(),
    FilesPage(),
    RecordsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final menu = context.select((AppState s) => s.navIsMenu);
    final backendOk = context.select((AppState s) => s.backendOk);
    final starting = context.select((AppState s) => s.startingBackend);
    final backendNote = context.select((AppState s) => s.backendNote);
    final backendError = context.select((AppState s) => s.backendError);
    final isDark = context.isDark;
    return NavScope(
      index: index,
      go: _selectTab,
      menuMode: menu,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Column(
          children: [
            if (!backendOk || starting)
              Material(
                color: starting ? (isDark ? AppColors.surface2 : const Color(0xFFEAEEF2)) : (isDark ? AppColors.errorPanel : const Color(0xFFFFEBE9)),
                child: TopSafePad(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                    child: Row(
                      children: [
                        Icon(
                          starting ? Icons.hourglass_top : Icons.warning_amber,
                          size: 16,
                          color: starting ? (isDark ? AppColors.textMuted : const Color(0xFF59636E)) : (isDark ? AppColors.dangerSoft : const Color(0xFFD1242F)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            starting
                                ? (backendNote ?? '启动后端…')
                                : (backendError ?? '后端未连接'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: starting ? (isDark ? AppColors.textMuted : const Color(0xFF59636E)) : (isDark ? AppColors.dangerSoft : const Color(0xFFD1242F)),
                            ),
                          ),
                        ),
                        if (!starting)
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () => context.read<AppState>().bootstrap(),
                            child: const Text('重试', style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: index,
                children: _pages,
              ),
            ),
          ],
        ),
        bottomNavigationBar: menu
            ? null
            : NavigationBar(
                height: 64,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                selectedIndex: index,
                onDestinationSelected: _selectTab,
                destinations: [
                  for (var i = 0; i < AppNav.labels.length; i++)
                    NavigationDestination(
                      icon: Icon(AppNav.icons[i], size: 22),
                      selectedIcon: Icon(AppNav.selectedIcons[i], size: 22),
                      label: AppNav.labels[i],
                    ),
                ],
              ),
      ),
    );
  }
}
