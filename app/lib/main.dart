import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_ai_agent/api/client.dart';
import 'package:ssh_ai_agent/pages/agent_page.dart';
import 'package:ssh_ai_agent/pages/hosts_page.dart';
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
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0D1117),
        ),
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  static const pages = [
    HostsPage(),
    AgentPage(),
    TerminalPage(),
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
                    ? (state.backendNote ?? '正在启动本机后端…')
                    : (state.backendError ?? '后端未连接'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              leading: Icon(
                state.startingBackend ? Icons.hourglass_top : Icons.warning_amber,
              ),
              actions: [
                TextButton(
                  onPressed: state.startingBackend ? null : () => state.bootstrap(),
                  child: const Text('重试'),
                ),
              ],
            ),
          Expanded(child: pages[index]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dns_outlined), label: '主机'),
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), label: 'Agent'),
          NavigationDestination(icon: Icon(Icons.terminal), label: '终端'),
          NavigationDestination(icon: Icon(Icons.history), label: '记录'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
        ],
      ),
    );
  }
}
