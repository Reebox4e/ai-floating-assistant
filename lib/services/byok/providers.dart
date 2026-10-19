/// BYOK provider registry — one source of truth for every provider:
/// endpoint shape, default model, and the 1-click API-key studio deep links.
///
/// Providers follow two wire formats:
///   • Gemini        → native Google generateContent SSE format
///   • OpenAI-compat → /chat/completions SSE (Groq, OpenRouter, NVIDIA NIM, Kimi)
class ProviderSpec {
  final String id;
  final String label;
  final bool openAiCompatible;
  final String baseUrl;      // base, no trailing slash
  final String defaultModel;
  final String keysUrl;      // 1-click onboarding deep link
  final String keyHeader;    // header style
  final bool keyAsQueryParam; // Gemini uses ?key=

  const ProviderSpec({
    required this.id,
    required this.label,
    required this.openAiCompatible,
    required this.baseUrl,
    required this.defaultModel,
    required this.keysUrl,
    this.keyHeader = 'Authorization',
    this.keyAsQueryParam = false,
  });
}

const kProviders = <ProviderSpec>[
  ProviderSpec(
    id: 'gemini',
    label: 'Google Gemini',
    openAiCompatible: false,
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    defaultModel: 'gemini-1.5-flash',
    keysUrl: 'https://aistudio.google.com/apikey',
    keyAsQueryParam: true,
  ),
  ProviderSpec(
    id: 'groq',
    label: 'Groq',
    openAiCompatible: true,
    baseUrl: 'https://api.groq.com/openai/v1',
    defaultModel: 'llama-3.1-8b-instant',
    keysUrl: 'https://console.groq.com/keys',
  ),
  ProviderSpec(
    id: 'openrouter',
    label: 'OpenRouter',
    openAiCompatible: true,
    baseUrl: 'https://openrouter.ai/api/v1',
    defaultModel: 'meta-llama/llama-3.1-8b-instruct',
    keysUrl: 'https://openrouter.ai/settings/keys',
  ),
  ProviderSpec(
    id: 'nvidia',
    label: 'NVIDIA NIM',
    openAiCompatible: true,
    baseUrl: 'https://integrate.api.nvidia.com/v1',
    defaultModel: 'meta/llama-3.1-8b-instruct',
    keysUrl: 'https://build.nvidia.com/settings/api-keys',
  ),
  ProviderSpec(
    id: 'kimi',
    label: 'Kimi (Moonshot AI)',
    openAiCompatible: true,
    baseUrl: 'https://api.moonshot.ai/v1',
    defaultModel: 'moonshot-v1-8k',
    keysUrl: 'https://platform.moonshot.cn/console/api-keys',
  ),
];

ProviderSpec? providerById(String id) =>
    kProviders.firstWhere((p) => p.id == id, orElse: () => null);
