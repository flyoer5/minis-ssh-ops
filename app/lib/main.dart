import 'package:flutter/material.dart';
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
import 'package:ssh_ai_agent/widgets/ime_inset.dart';
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
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
    final ready = context.select((AppState s) => s.bootstrapped);
    if (!ready) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accentSoft),
              ),
              SizedBox(height: 14),
              Text(
                '启动中…',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
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
    // Select only shell fields — full watch() rebuilds every Agent stream tick.
    final menu = context.select((AppState s) => s.navIsMenu);
    final backendOk = context.select((AppState s) => s.backendOk);
    final starting = context.select((AppState s) => s.startingBackend);
    final backendNote = context.select((AppState s) => s.backendNote);
    final backendError = context.select((AppState s) => s.backendError);
    return NavScope(
      index: index,
      go: (i) => setState(() => index = i),
      menuMode: menu,
      // Shell: resizeToAvoidBottomInset false so IndexedStack tabs do not
      // double-shrink. Do NOT wrap with WithoutViewInsets — that zeroed
      // viewInsets for every form TextField (settings/hosts/etc).
      // Agent/terminal freeze only their message/scroll subtrees.
      child: Scaffold(
        backgroundColor: AppColors.bg,
        resizeToAvoidBottomInset: false,
        body: Column(
          children: [
            if (!backendOk || starting)
              Material(
                color: starting ? AppColors.surface2 : AppColors.errorPanel,
                child: TopSafePad(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                    child: Row(
                      children: [
                        Icon(
                          starting ? Icons.hourglass_top : Icons.warning_amber,
                          size: 16,
                          color: starting ? AppColors.textMuted : AppColors.dangerSoft,
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
                              color: starting ? AppColors.textMuted : AppColors.dangerSoft,
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
        // Always keep NavigationBar mounted. Hiding it on IME open (even with a
        // local StatefulWidget) changes Scaffold body size and dismisses the
        // Agent keyboard. Composer ImeInset uses reservedBottom instead.
        bottomNavigationBar: menu
            ? null
            : NavigationBar(
                height: 56,
                backgroundColor: AppColors.surface,
                surfaceTintColor: Colors.transparent,
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
