import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'providers.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// MODULE 3 — BYOK API Manager
/// Extensible HTTP client for Gemini / Groq / OpenRouter / NVIDIA NIM / Kimi
/// with SSE streaming. Keys are read from the encrypted vault, never logged.
/// ─────────────────────────────────────────────────────────────────────────

class ChatTurn {
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  const ChatTurn({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

abstract class ByokProvider {
  final ProviderSpec spec;
  final Dio _dio = Dio();

  ByokProvider(this.spec);

  /// Streams assistant text tokens as they arrive over SSE.
  Stream<String> streamChat({
    required String apiKey,
    required List<ChatTurn> messages,
    String? model,
  });

  Uri buildUri(String model, String apiKey) =>
      Uri.parse('${spec.baseUrl}${_path(model)}${_authSuffix(apiKey)}');

  String _path(String model) => spec.openAiCompatible
      ? '/chat/completions'
      : '/models/$model:streamGenerateContent';

  String _authSuffix(String apiKey) =>
      spec.keyAsQueryParam ? '?alt=sse&key=$apiKey' : '';

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (!spec.keyAsQueryParam)
          'Authorization': 'Bearer ', // key injected in _send for safety
      };

  /// Shared SSE engine: POST → parse "data: {...}" frames → yield deltas.
  Stream<String> _sendSse({
    required Uri uri,
    required String apiKey,
    required Map<String, dynamic> body,
    required String Function(Map<String, dynamic>) extractDelta,
  }) async* {
    final dio = Dio();
    final response = await dio.post<ResponseBody>(
      uri.toString(),
      data: body,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Content-Type': 'application/json',
          if (!spec.keyAsQueryParam) 'Authorization': 'Bearer $apiKey',
        },
      ),
    );

    final stream = response.data!.stream;
    var buffer = '';

    await for (final chunk in stream) {
      buffer += utf8.decode(chunk, allowMalformed: true);

      // SSE frames are newline-delimited; a frame looks like:  data: {...}
      while (buffer.contains('\n')) {
        final line = buffer.substring(0, buffer.indexOf('\n')).trim();
        buffer = buffer.substring(buffer.indexOf('\n') + 1);

        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload == '[DONE]') return;
        if (payload.isEmpty) continue;

        try {
          final json = jsonDecode(payload) as Map<String, dynamic>;
          final delta = extractDelta(json);
          if (delta.isNotEmpty) yield delta;
        } catch (_) {/* keep-alive frames / partial JSON — ignore */ }
      }
    }
  }
}

/// OpenAI-compatible wire format (Groq, OpenRouter, NVIDIA NIM, Kimi)
class OpenAiCompatProvider extends ByokProvider {
  OpenAiCompatProvider(super.spec);

  @override
  Stream<String> streamChat({
    required String apiKey,
    required List<ChatTurn> messages,
    String? model,
  }) {
    final m = model ?? spec.defaultModel;
    return _sendSse(
      uri: buildUri(m, apiKey),
      apiKey: apiKey,
      body: {
        'model': m,
        'stream': true,
        'messages': messages.map((t) => t.toJson()).toList(),
      },
      extractDelta: (json) {
        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) return '';
        return (((choices.first as Map)['delta']
                as Map?)?['content'] as String?) ??
            '';
      },
    );
  }
}

/// Google Gemini native wire format
class GeminiProvider extends ByokProvider {
  GeminiProvider(super.spec);

  @override
  Stream<String> streamChat({
    required String apiKey,
    required List<ChatTurn> messages,
    String? model,
  }) {
    final m = model ?? spec.defaultModel;
    return _sendSse(
      uri: buildUri(m, apiKey),
      apiKey: apiKey,
      body: {
        'contents': messages
            .map((t) => {
                  'role': t.role == 'assistant' ? 'model' : 'user',
                  'parts': [
                    {'text': t.content}
                  ]
                })
            .toList(),
      },
      extractDelta: (json) {
        final candidates = json['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) return '';
        final parts =
            ((candidates.first as Map)['content'] as Map?)?['parts'] as List?;
        if (parts == null || parts.isEmpty) return '';
        return ((parts.first as Map)['text'] as String?) ?? '';
      },
    );
  }
}

/// The manager the rest of the app talks to.
/// Key resolution is injected (EncryptedDbService/SecureStorage provides it).
class ByokApiManager {
  final String Function(String providerId) apiKeyResolver;

  ByokApiManager({required this.apiKeyResolver});

  final _cache = <String, ByokProvider>{};

  ByokProvider _provider(String id) {
    final spec = providerById(id);
    if (spec == null) throw ArgumentError('Unknown provider: $id');
    return _cache.putIfAbsent(
      id,
      () => spec.openAiCompatible
          ? OpenAiCompatProvider(spec)
          : GeminiProvider(spec),
    );
  }

  /// Stream a full conversation.
  Stream<String> streamChat(
    String providerId, {
    required List<ChatTurn> messages,
    String? model,
  }) {
    final key = apiKeyResolver(providerId);
    if (key.isEmpty) throw StateError(
        'No API key for $providerId. Add one from Settings → Providers.');
    return _provider(providerId)
        .streamChat(apiKey: key, messages: messages, model: model);
  }

  /// Convenience: single prompt → concatenated answer.
  Future<String> ask(
    String providerId,
    String prompt, {
    List<ChatTurn> history = const [],
    String? model,
  }) async {
    final turns = [...history, ChatTurn(role: 'user', content: prompt)];
    final buffer = StringBuffer();
    await for (final token in streamChat(providerId,
        messages: turns, model: model)) {
      buffer.write(token);
    }
    return buffer.toString();
  }
}
