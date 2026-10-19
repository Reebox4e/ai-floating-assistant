import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/byok/byok_api_manager.dart';

/// Secondary Dart entrypoint — the UI rendered INSIDE the floating overlay
/// panel (see FloatingOverlayService.kt: OVERLAY_ENTRYPOINT = "overlayMain").
@pragma('vm:entry-point')
void overlayMain() {
  runApp(const OverlayChatApp());
}

const _overlayChannel = MethodChannel('afa/overlay');

class OverlayChatApp extends StatelessWidget {
  const OverlayChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4B39EF),
        useMaterial3: true,
      ),
      home: const OverlayChatScreen(),
    );
  }
}

class OverlayChatScreen extends StatefulWidget {
  const OverlayChatScreen({super.key});
  @override
  State<OverlayChatScreen> createState() => _OverlayChatScreenState();
}

class _OverlayChatScreenState extends State<OverlayChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<(String, String)> _messages = []; // (role, text)
  String _streamingAnswer = '';

  /// BYOK engine — keys resolved from secure storage (wire in prod).
  late final ByokApiManager _byok = ByokApiManager(
    apiKeyResolver: (providerId) => '', // TODO: read key from secure storage
  );

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    setState(() {
      _messages.add(('user', text));
      _streamingAnswer = '';
    });

    try {
      final turns = _messages.map((m) => ChatTurn(role: m.$1, content: m.$2)).toList();
      final stream = _byok.streamChat('gemini', messages: turns);
      await for (final token in stream) {
        setState(() => _streamingAnswer += token);
      }
      setState(() {
        _messages.add(('assistant', _streamingAnswer));
        _streamingAnswer = '';
      });
    } catch (e) {
      setState(() {
        _messages.add(('assistant', 'Error: $e'));
        _streamingAnswer = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = _messages.length + (_streamingAnswer.isNotEmpty ? 1 : 0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.minimize),
            onPressed: () => _overlayChannel.invokeMethod('minimize'),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _overlayChannel.invokeMethod('close'),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            itemCount: itemCount,
            itemBuilder: (context, i) {
              if (_streamingAnswer.isNotEmpty && i == 0) {
                return _bubble('assistant', _streamingAnswer);
              }
              final idx = _messages.length - 1 - (i - (_streamingAnswer.isNotEmpty ? 1 : 0));
              final m = _messages[idx];
              return _bubble(m.$1, m.$2);
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Ask anything…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(icon: const Icon(Icons.send), onPressed: _send),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bubble(String role, String text) => Align(
        alignment:
            role == 'user' ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: role == 'user'
                ? const Color(0xFF4B39EF)
                : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: TextStyle(
                color: role == 'user' ? Colors.white : Colors.black87),
          ),
        ),
      );
}
