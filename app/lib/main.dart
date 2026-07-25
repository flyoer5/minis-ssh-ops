import 'package:flutter/material.dart';
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
import 'package:ssh_ai_agent/widgets/nav_menu.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Never leave the user stuck on the default red/yellow ErrorWidget.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return _AppErrorSurface(details: details);
  };
  runApp(const SshAiAgentApp());
}

/// In-app recovery UI when a build/layout throws (instead of full-screen red).
class _AppErrorSurface extends StatelessWidget {
  const _AppErrorSurface({required this.details});
  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final msg = details.exceptionAsString();
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
              const SizedBox(height: 12),
              const Text(
                '界面出错了',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text),
              ),
              const SizedBox(height: 8),
              const Text(
                '通常是某次操作触发了异常。可返回继续用；若反复出现请到设置导出日志。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      msg,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.dangerSoft),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  // Best-effort: pop if possible; otherwise user can switch tabs via process restart.
                  final nav = Navigator.maybeOf(context);
                  if (nav != null && nav.canPop()) {
                    nav.pop();
                  }
                },
                child: const Text('关闭此页'),
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
      child: MaterialApp(
        title: '机枢',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        builder: (context, child) {
          // Keep ErrorWidget theme-consistent even outside routes.
          ErrorWidget.builder = (FlutterErrorDetails details) {
            return _AppErrorSurface(details: details);
          };
          return child ?? const SizedBox.shrink();
        },
        home: const RootGate(),
      ),
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.bootstrapped || state.startingBackend) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('启动中…'),
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
    final state = context.watch<AppState>();
    final menu = state.navIsMenu;
    return NavScope(
      index: index,
      go: (i) => setState(() => index = i),
      menuMode: menu,
      child: Scaffold(
        body: Column(
          children: [
            if (!state.backendOk || state.startingBackend)
              Material(
                color: state.startingBackend ? AppColors.surface2 : AppColors.errorPanel,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                    child: Row(
                      children: [
                        Icon(
                          state.startingBackend ? Icons.hourglass_top : Icons.warning_amber,
                          size: 16,
                          color: state.startingBackend ? AppColors.textMuted : AppColors.dangerSoft,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.startingBackend
                                ? (state.backendNote ?? '启动后端…')
                                : (state.backendError ?? '后端未连接'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: state.startingBackend ? AppColors.textMuted : AppColors.dangerSoft,
                            ),
                          ),
                        ),
                        if (!state.startingBackend)
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () => state.bootstrap(),
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
                height: 56,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                selectedIndex: index,
                onDestinationSelected: (i) => setState(() => index = i),
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
