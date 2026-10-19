import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/automation/native_bridge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Firebase is optional at build time — enable after adding google-services.json
  // await Firebase.initializeApp();

  runApp(const AssistantApp());
}

class AssistantApp extends StatelessWidget {
  const AssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Floating Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4B39EF), useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _status = 'Checking permissions…';

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _listenNotificationAutoReplies();
  }

  Future<void> _checkPermissions() async {
    final overlay = await NativeBridge.canDrawOverlays();
    final accessibility = await NativeBridge.isAccessibilityConnected();
    setState(() {
      _status = 'Overlay: ${overlay ? "OK" : "NOT GRANTED"}  |  '
          'Accessibility: ${accessibility ? "OK" : "NOT GRANTED"}';
    });
  }

  /// mybot://run?skill=xxx → replay skill; mybot://chat → open bubble.
  /// Production: use the app_links package to receive these.
  void handleDeepLink(Uri uri) {
    if (uri.host == 'run') {
      final skillId = uri.queryParameters['skill'];
      if (skillId != null) NativeBridge.replaySkillById(skillId);
    }
    if (uri.host == 'chat') {
      NativeBridge.showBubble();
    }
  }

  /// Intercepted notifications → AI auto-reply (wire to BYOK in prod).
  void _listenNotificationAutoReplies() {
    NativeBridge.notificationEvents.receiveBroadcastStream().listen((raw) {
      final notif = jsonDecode(raw.toString()) as Map<String, dynamic>;
      debugPrint('Notification from ${notif['package']}: ${notif['text']}');
      // TODO: generate reply via ByokApiManager and inject it into the
      // source app via NativeBridge.replay(...) or RemoteInput.
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Floating Assistant')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(_status, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          icon: const Icon(Icons.bubble_chart),
          label: const Text('Start floating bubble'),
          onPressed: () async {
            if (!await NativeBridge.canDrawOverlays()) {
              await NativeBridge.requestOverlayPermission();
              return;
            }
            await NativeBridge.showBubble();
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.accessibility_new),
          label: const Text('Grant Accessibility (automation)'),
          onPressed: NativeBridge.openAccessibilitySettings,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.notifications_active),
          label: const Text('Grant Notification access (auto-replies)'),
          onPressed: NativeBridge.openNotificationAccessSettings,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.fiber_manual_record),
          label: const Text('Record a new skill'),
          onPressed: () async {
            await NativeBridge.recordStart();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Recording… interact with any app, then stop.')));
            }
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.stop),
          label: const Text('Stop recording'),
          onPressed: () async {
            final stepsJson = await NativeBridge.recordStop();
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Recorded: $stepsJson')));
            }
          },
        ),
      ]),
    );
  }
}
