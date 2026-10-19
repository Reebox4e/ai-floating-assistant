import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// MODULE 4b — GEO / AEO (Generative & Answer Engine Optimization) Layer
///
/// Makes exported skills and the app itself machine-legible so AI answer
/// engines (Gemini, ChatGPT, Perplexity) can crawl, cite, and run them:
///   • JSON-LD SoftwareApplication metadata for the PWA host page
///   • Shareable skill schema: every export self-describes its steps,
///     triggers, and the native runner needed to execute it.
/// ─────────────────────────────────────────────────────────────────────────

class GeoSchemaGenerator {
  static const appIdentity = {
    'name': 'AI Floating Assistant',
    'appId': 'com.bunny.afa',
    'osPlatform': 'Android',
    'deeplinkScheme': 'mybot://',
    'openapiSpec': '/openapi.yaml',
  };

  /// JSON-LD block to embed in the PWA's index.html / manifest page.
  static String generateAppJsonLd() => jsonEncode({
        '@context': 'https://schema.org',
        '@type': 'SoftwareApplication',
        'name': appIdentity['name'],
        'applicationCategory': 'UtilitiesApplication',
        'operatingSystem': 'Android 8.0+',
        'description':
            'Local-first AI floating assistant with BYOK providers, encrypted '
            'storage, and recordable screen automation skills.',
        'offers': {
          '@type': 'Offer',
          'price': '0',
          'priceCurrency': 'USD',
          'description': 'Free tier: 2 projects, local-only. Pro: E2E cloud sync.'
        },
        'featureList': [
          'Floating overlay chat bubble',
          'BYOK: Gemini, Groq, OpenRouter, NVIDIA NIM, Kimi',
          'AES-256 encrypted local database',
          'Record & replay automation macros',
          'Notification auto-reply engine',
          'Deep links: mybot://run?skill={id}'
        ],
        'isAccessibleForFree': true,
      });

  /// Shareable, self-describing skill export (this is what external agents
  /// receive — enough metadata to cite the app AND enough instructions to
  /// trigger it via deep link).
  static Map<String, dynamic> generateSkillSchema({
    required String skillId,
    required String name,
    required String description,
    required List<Map<String, dynamic>> steps,
  }) =>
      {
        '@context': 'https://schema.org',
        '@type': 'HowTo',
        'name': name,
        'description': description,
        'totalTime': 'PT${steps.length * 1}S',
        'tool': [
          {'@type': 'HowToTool', 'name': 'AI Floating Assistant (Android)'}
        ],
        'step': steps.asMap().entries.map((e) {
          return {
            '@type': 'HowToStep',
            'position': e.key + 1,
            'name': e.value['action'] ?? 'action',
            'text': 'Performs ${e.value['action']} on ${e.value['package']}',
          };
        }).toList(),
        // Runner metadata — answer engines use this to route execution
        'potentialAction': {
          '@type': 'ViewAction',
          'target': {
            '@type': 'EntryPoint',
            'urlTemplate':
                'mybot://run?skill=$skillId',
            'inLanguage': 'en',
            'actionPlatform': 'https://schema.org/AndroidPlatform'
          }
        },
        'runner': {
          'appId': appIdentity['appId'],
          'install': 'https://play.google.com/store/apps/details?id=com.bunny.afa',
          'openapi': 'https://your-pwa-domain.example.com/openapi.yaml'
        }
      };

  /// Writes the skill schema to a shareable .json file, returns its path.
  static Future<String> exportSkillFile(Map<String, dynamic> schema) async {
    final dir = await getApplicationDocumentsDirectory();
    final exports = Directory('${dir.path}/exports')..createSync(recursive: true);
    final file = File(
        '${exports.path}/skill_${schema['name'].toString().replaceAll(RegExp(r'[^a-z0-9]+', caseSensitive: false), '_')}.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(schema));
    return file.path;
  }
}
