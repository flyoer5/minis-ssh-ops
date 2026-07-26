import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Match Android windowBackground (#0D1117) — no flash of wrong color.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: AppColors.bg,
      systemNavigationBarIconBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  final state = AppState();
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const SshAiApp(),
    ),
  );
  // Defer native backend start until after first frame so UI paints immediately.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    state.bootstrap();
  });
}

class SshAiApp extends StatelessWidget {
  const SshAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '机枢',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final scale = mq.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.15,
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: scale),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const RootGate(),
    );
  }
}

/// Route side-effects (host select / terminal / files) after the frame so
/// [build] never triggers [notifyListeners] (which would re-enter providers).
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  String? _scheduledHost;
  String? _scheduledTerm;
  String? _scheduledFiles;

  @override
  Widget build(BuildContext context) {
    final ready = context.select((AppState s) => s.ready);
    final selectedHostId = context.select((AppState s) => s.selectedHostId);
    final openTerminalHostId =
        context.select((AppState s) => s.openTerminalHostId);
    final openFilesHostId = context.select((AppState s) => s.openFilesHostId);

    if (ready && selectedHostId != null && selectedHostId != _scheduledHost) {
      _scheduledHost = selectedHostId;
      final id = selectedHostId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final s = context.read<AppState>();
        if (s.selectedHostId == id) s.selectHost(id);
      });
    }
    if (selectedHostId == null) _scheduledHost = null;

    if (openTerminalHostId != null && openTerminalHostId != _scheduledTerm) {
      _scheduledTerm = openTerminalHostId;
      final id = openTerminalHostId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final s = context.read<AppState>();
        if (s.openTerminalHostId == id) {
          s.clearOpenTerminal();
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => TerminalPage(hostId: id)),
          );
        }
        if (mounted) setState(() => _scheduledTerm = null);
      });
    }

    if (openFilesHostId != null && openFilesHostId != _scheduledFiles) {
      _scheduledFiles = openFilesHostId;
      final id = openFilesHostId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final s = context.read<AppState>();
        if (s.openFilesHostId == id) {
          s.clearOpenFiles();
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => FilesPage(hostId: id)),
          );
        }
        if (mounted) setState(() => _scheduledFiles = null);
      });
    }

    if (!ready) {
      final note = context.select((AppState s) => s.backendNote);
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 14),
              Text(
                note ?? '启动中…',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
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

  static const _pages = <Widget>[
    HostsPage(),
    AgentPage(),
    RecordsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final backendOk = context.select((AppState s) => s.backendOk);
    final starting = context.select((AppState s) => s.backendStarting);
    final backendNote = context.select((AppState s) => s.backendNote);
    final backendError = context.select((AppState s) => s.backendError);
    final menu = context.select((AppState s) => s.navStyle == 'menu');

    return NavScope(
      index: index,
      go: (i) => setState(() => index = i),
      child: Scaffold(
        // Do not resize shell with IME (avoids double-shrink with tabs).
        // Do NOT wrap with WithoutViewInsets — that zeroed viewInsets for forms.
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
                          color: starting
                              ? AppColors.textMuted
                              : AppColors.dangerSoft,
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
                              color: starting
                                  ? AppColors.textMuted
                                  : AppColors.dangerSoft,
                            ),
                          ),
                        ),
                        if (!starting)
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () =>
                                context.read<AppState>().bootstrap(),
                            child: const Text('重试',
                                style: TextStyle(fontSize: 12)),
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
        // ImeAwareBottomBar setStates only itself — does not rebuild Agent.
        bottomNavigationBar: menu
            ? null
            : ImeAwareBottomBar(
                child: NavigationBar(
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
      ),
    );
  }
}
