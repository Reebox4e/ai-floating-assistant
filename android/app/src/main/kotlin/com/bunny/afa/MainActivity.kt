package com.bunny.afa

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import accessibility.AssistantAccessibilityService
import notifications.NotificationReceiverService

/**
 * Main entry. Registers all native bridges:
 *   afa/control              → overlay + permission flows
 *   afa/automation (+events) → record / replay accessibility commands
 *   afa/notification_events  → intercepted notifications
 */
class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL_CONTROL = "afa/control"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Automation + notification bridges (services push through these)
        AssistantAccessibilityService.registerChannels(messenger)
        NotificationReceiverService.registerChannels(messenger)

        MethodChannel(messenger, CHANNEL_CONTROL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showBubble" -> {
                    startService(Intent(this, overlay.FloatingOverlayService::class.java))
                    result.success(true)
                }
                "hideBubble" -> {
                    stopService(Intent(this, overlay.FloatingOverlayService::class.java))
                    result.success(true)
                }
                "canDrawOverlays" ->
                    result.success(android.provider.Settings.canDrawOverlays(this))
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                        !android.provider.Settings.canDrawOverlays(this)) {
                        startActivity(
                            Intent(
                                android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                android.net.Uri.parse("package:$packageName")
                            )
                        )
                    }
                    result.success(true)
                }
                "openAccessibilitySettings" -> {
                    startActivity(Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(true)
                }
                "openNotificationAccessSettings" -> {
                    startActivity(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
