import 'dart:convert';
import 'package:flutter/services.dart';
import '../storage/encrypted_db_service.dart';

/// All native bridges in one place:
///   afa/control              → overlay + permission flows
///   afa/automation           → record / replay commands
///   afa/automation_events    → recorded steps streamed from Kotlin
///   afa/notification_events  → intercepted notifications
class NativeBridge {
  static const _control = MethodChannel('afa/control');
  static const _automation = MethodChannel('afa/automation');

  static const automationEvents = EventChannel('afa/automation_events');
  static const notificationEvents = EventChannel('afa/notification_events');

  // ── Overlay ──
  static Future<void> showBubble() => _control.invokeMethod('showBubble');
  static Future<void> hideBubble() => _control.invokeMethod('hideBubble');
  static Future<bool> canDrawOverlays() async =>
      await _control.invokeMethod('canDrawOverlays') ?? false;
  static Future<void> requestOverlayPermission() =>
      _control.invokeMethod('requestOverlayPermission');
  static Future<void> openAccessibilitySettings() =>
      _control.invokeMethod('openAccessibilitySettings');
  static Future<void> openNotificationAccessSettings() =>
      _control.invokeMethod('openNotificationAccessSettings');

  // ── Automation: record & replay ──
  static Future<bool> isAccessibilityConnected() async {
    try {
      return await _automation.invokeMethod('isConnected') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> recordStart() => _automation.invokeMethod('recordStart');

  /// Returns the recorded macro JSON (list of steps).
  static Future<String> recordStop() async =>
      await _automation.invokeMethod('recordStop') ?? '[]';

  static Future<void> replay(List<Map<String, dynamic>> steps) =>
      _automation.invokeMethod('replay', {'stepsJson': jsonEncode(steps)});

  static Future<String?> inspectActiveWindow() async =>
      await _automation.invokeMethod('inspect');

  /// Convenience: load a skill from the encrypted DB and replay it.
  static Future<void> replaySkillById(String skillId) async {
    final db = EncryptedDbService.instance;
    await db.init();
    final skill = await db.skill(skillId);
    if (skill == null) return;
    final stepsRaw = skill['steps_json'] as String? ?? '[]';
    final steps = (jsonDecode(stepsRaw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    await replay(steps);
  }
}
