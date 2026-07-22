import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/pages/agent_page.dart';
import 'package:ssh_ai_agent/pages/files_page.dart';
import 'package:ssh_ai_agent/pages/hosts_page.dart';
import 'package:ssh_ai_agent/pages/onboarding_page.dart';
import 'package:ssh_ai_agent/pages/records_page.dart';
import 'package:ssh_ai_agent/pages/settings_page.dart';
import 'package:ssh_ai_agent/pages/terminal_page.dart';
import 'package:ssh_ai_agent/state/app_state.dart';

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
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F81F7), brightness: Brightness.dark),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0D1117),
        ),
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
    if (!state.onboarded) {
      return OnboardingPage(onDone: () {});
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

  // Keep State alive across tab switches (terminal session, chat, probes).
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
    return Scaffold(
      body: Column(
        children: [
          if (!state.backendOk || state.startingBackend)
            MaterialBanner(
              content: Text(
                state.startingBackend
                    ? (state.backendNote ?? '启动后端…')
                    : (state.backendError ?? '后端未连接'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              leading: Icon(state.startingBackend ? Icons.hourglass_top : Icons.warning_amber),
              actions: [
                TextButton(
                  onPressed: state.startingBackend ? null : () => state.bootstrap(),
                  child: const Text('重试'),
                ),
              ],
            ),
          Expanded(
            child: IndexedStack(
              index: index,
              children: _pages,
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dns_outlined), label: '主机'),
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), label: 'Agent'),
          NavigationDestination(icon: Icon(Icons.terminal), label: '终端'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), label: '文件'),
          NavigationDestination(icon: Icon(Icons.history), label: '记录'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
        ],
      ),
    );
  }
}
