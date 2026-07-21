import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/opsd_service.dart';
import 'pages/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const MinisSshOpsApp());
}

class MinisSshOpsApp extends StatefulWidget {
  const MinisSshOpsApp({super.key});

  @override
  State<MinisSshOpsApp> createState() => _MinisSshOpsAppState();
}

class _MinisSshOpsAppState extends State<MinisSshOpsApp> with WidgetsBindingObserver {
  final OpsdService _opsd = OpsdService.instance;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  Future<void> _boot() async {
    try {
      await _opsd.start();
      if (!mounted) return;
      setState(() {
        _ready = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ready = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // keep opsd running while app process lives; stop on detach if desired
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _opsd.ensureRunning();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Minis SSH Ops',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F1419),
      ),
      home: _error != null
          ? _BootError(error: _error!, onRetry: _boot)
          : _ready
              ? HomePage(opsd: _opsd)
              : const _BootSplash(),
    );
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在启动本地运维服务…'),
          ],
        ),
      ),
    );
  }
}

class _BootError extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _BootError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            const Text('opsd 启动失败', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(error, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
