# 🐰 AI Floating Assistant — Android (Flutter + Kotlin)

Local-first AI floating assistant: overlay bubble chat, BYOK providers,
AES-256 encrypted storage, record & replay screen automation, notification
auto-replies, daily schedules, GEO/AEO metadata, and PWA dashboard.

## Folder structure

```
ai_floating_assistant/
├── pubspec.yaml
├── assets/
│   └── openapi.yaml                  ← Custom GPT / OpenAPI trigger spec (PWA)
├── android/app/src/main/
│   ├── AndroidManifest.xml          ← ALL permissions + services + deep links
│   ├── res/xml/
│   │   └── accessibility_service_config.xml
│   └── kotlin/com/bunny/afa/
│       ├── MainActivity.kt                    ← afa/control channel
│       ├── overlay/FloatingOverlayService.kt  ← MODULE 1: bubble + Flutter panel
│       ├── accessibility/AssistantAccessibilityService.kt
│       │                                       ← MODULE 2: node parser + record/replay
│       ├── notifications/NotificationReceiverService.kt
│       │                                       ← notification interception
│       ├── scheduler/SkillSchedulerWorker.kt  ← MODULE 5: WorkManager schedules
│       └── push/FcmTriggerService.kt          ← external-agent FCM triggers
└── lib/
    ├── main.dart                    ← app bootstrap + permission flows
    ├── overlay_entry.dart           ← overlayMain(): Flutter UI inside the bubble
    └── services/
        ├── byok/
        │   ├── providers.dart       ← provider registry + 1-click key links
        │   └── byok_api_manager.dart← MODULE 3: SSE streaming engine
        ├── storage/
        │   ├── encrypted_db_service.dart   ← MODULE 4a: SQLCipher AES-256
        │   └── geo_schema_generator.dart   ← MODULE 4b: GEO/AEO JSON-LD
        ├── automation/
        │   └── native_bridge.dart   ← all MethodChannel/EventChannel bridges
        └── sync/
            └── e2e_sync_service.dart← MODULE 6: Pro E2E cloud sync
```

## Permissions (why each is needed)

| Permission | Purpose |
|---|---|
| SYSTEM_ALERT_WINDOW | Floating bubble over any app |
| BIND_ACCESSIBILITY_SERVICE | Inspect nodes, auto-click, input text in other apps |
| BIND_NOTIFICATION_LISTENER_SERVICE | Intercept messages for AI auto-replies |
| SCHEDULE_EXACT_ALARM / RECEIVE_BOOT_COMPLETED | Daily routines survive reboot |
| QUERY_ALL_PACKAGES | Resolve node viewIds across apps |
| INTERNET | BYOK API calls (keys never leave the device) |

## BYOK providers & 1-click key onboarding

| Provider | Endpoint | Get key |
|---|---|---|
| Google Gemini | generativelanguage.googleapis.com/v1beta | https://aistudio.google.com/apikey |
| Groq | api.groq.com/openai/v1 | https://console.groq.com/keys |
| OpenRouter | openrouter.ai/api/v1 | https://openrouter.ai/settings/keys |
| NVIDIA NIM | https://integrate.api.nvidia.com/v1 | https://build.nvidia.com/settings/api-keys |
| Kimi (Moonshot) | api.moonshot.ai/v1 | https://platform.moonshot.cn/console/api-keys |

## Build

```bash
flutter pub get
flutter build apk --release          # Android
flutter build web --release          # PWA dashboard (same codebase)
```

Requires: Flutter 3.22+, Android SDK 34, minSdk 23.
For cloud CI without local setup: push to GitHub → connect Codemagic → it
builds the APK from this repo.

## First-run checklist (user flow)

1. Launch app → grant Overlay permission (auto-prompted)
2. Grant Accessibility access (Settings → Accessibility → AI Assistant Automation)
3. Grant Notification access (for auto-replies)
4. Add a provider API key in Settings (1-click deep links above)
5. Tap "Start floating bubble" → bubble appears → tap to expand chat

## Security model

- Chats/prompts/skills: SQLCipher AES-256, master key in Android Keystore-backed secure storage
- Provider API keys: secure storage only, never uploaded
- Pro sync: AES-256-GCM client-side; server sees ciphertext only
- Notification interception whitelist: WhatsApp/SMS only by default

## External agents (ChatGPT Custom Actions)

Deploy the PWA, publish `assets/openapi.yaml` at `/.well-known/openapi.yaml`,
register the user's FCM token, then a Custom GPT can call
`POST /skills/{id}/run` or the device handles `mybot://run?skill={id}`.
