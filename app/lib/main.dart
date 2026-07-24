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
  runApp(const SshAiAgentApp());
}

class SshAiAgentApp extends StatelessWidget {
  const SshAiAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(ApiClient())..bootstrap(),
      child: MaterialApp(
        title: 'SSH AI Agent',
        theme: buildAppTheme(),
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
