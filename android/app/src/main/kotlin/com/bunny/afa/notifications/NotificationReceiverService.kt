package com.bunny.afa.notifications

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject

/**
 * MODULE 3b — Notification Listener
 *
 * Intercepts incoming notifications (WhatsApp, SMS, etc.), extracts
 * sender + message, and streams them to Dart via "afa/notification_events"
 * so the BYOK engine can generate AI-assisted auto-replies.
 */
class NotificationReceiverService : NotificationListenerService() {

    companion object {
        var instance: NotificationReceiverService? = null
        var eventSink: EventChannel.EventSink? = null

        const val EVENT_CHANNEL = "afa/notification_events"

        /** Privacy whitelist — only these packages are intercepted. */
        val allowedPackages = setOf(
            "com.whatsapp",
            "com.whatsapp.w4b",
            "com.google.android.apps.messaging",
            "com.android.mms",
            "com.samsung.android.messaging"
        )

        fun registerChannels(messenger: BinaryMessenger) {
            EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                        eventSink = sink
                    }
                    override fun onCancel(args: Any?) { eventSink = null }
                }
            )
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
    }

    override fun onListenerDisconnected() {
        instance = null
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        if (sbn.packageName !in allowedPackages) return // privacy gate

        val extras = sbn.notification?.extras ?: return
        val title =
            extras.getCharSequence(android.app.Notification.EXTRA_TITLE)?.toString() ?: ""
        val text =
            extras.getCharSequence(android.app.Notification.EXTRA_TEXT)?.toString() ?: ""

        val payload = JSONObject().apply {
            put("package", sbn.packageName)
            put("title", title)
            put("text", text)
            put("postedAt", sbn.postTime)
        }

        eventSink?.success(payload.toString())
    }
}
