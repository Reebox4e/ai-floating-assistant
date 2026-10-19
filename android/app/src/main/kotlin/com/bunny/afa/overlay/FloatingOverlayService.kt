package com.bunny.afa.overlay

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import io.flutter.FlutterEngineGroup
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * MODULE 1 — Floating Overlay Service
 *
 * A foreground service that renders:
 *  1. A draggable floating bubble (TYPE_APPLICATION_OVERLAY)
 *  2. On tap, expands into a full Flutter-rendered chat panel
 *     (secondary Dart entrypoint: `overlayMain` in lib/overlay_entry.dart)
 *
 * Requires SYSTEM_ALERT_WINDOW. Start it from Dart via the "afa/control" channel.
 */
class FloatingOverlayService : Service() {

    companion object {
        const val CHANNEL_FLUTTER = "afa/overlay"
        const val OVERLAY_ENTRYPOINT = "overlayMain"
        private var engine: FlutterEngine? = null

        /** Lets the Dart overlay UI close/minimize itself. */
        var methodChannel: MethodChannel? = null
    }

    private lateinit var windowManager: WindowManager
    private var bubbleView: View? = null
    private var panelView: View? = null
    private var expanded = false

    // ───────────────────────── Lifecycle ─────────────────────────

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        startAsForeground()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (bubbleView == null) showBubble()
        return START_STICKY
    }

    override fun onDestroy() {
        bubbleView?.let { windowManager.removeView(it) }
        panelView?.let { windowManager.removeView(it) }
        bubbleView = null
        panelView = null
        engine?.destroy()
        engine = null
        super.onDestroy()
    }

    // ───────────────────────── Foreground ─────────────────────────

    private fun startAsForeground() {
        val channelId = "afa_overlay"
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(channelId, "AI Assistant Overlay", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val notification: Notification =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                Notification.Builder(this, channelId).setContentTitle("AI Assistant active")
                    .setSmallIcon(android.R.drawable.ic_menu_compass).build()
            else
                @Suppress("DEPRECATION")
                Notification.Builder(this).setContentTitle("AI Assistant active")
                    .setSmallIcon(android.R.drawable.ic_menu_compass).build()
        startForeground(1001, notification)
    }

    // ───────────────────────── Bubble ─────────────────────────

    @SuppressLint("ClickableViewAccessibility")
    private fun showBubble() {
        val bubble = android.widget.TextView(this).apply {
            text = "🐰"
            textSize = 22f
            setPadding(18, 10, 18, 10)
            background = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.OVAL
                setColor(0xFF4B39EF.toInt())
            }
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 40
            y = 300
        }

        // Drag + tap-to-expand handling
        var downX = 0f; var downY = 0f; var startX = 0; var startY = 0
        var moved = false
        bubble.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX; downY = event.rawY
                    startX = params.x; startY = params.y
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - downX).toInt()
                    val dy = (event.rawY - downY).toInt()
                    if (dx * dx + dy * dy > 100) moved = true
                    params.x = startX + dx
                    params.y = startY + dy
                    windowManager.updateViewLayout(bubble, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) togglePanel()
                    true
                }
                else -> false
            }
        }

        windowManager.addView(bubble, params)
        bubbleView = bubble
    }

    // ───────────────────────── Expanded chat panel (Flutter UI) ─────────────────────────

    private fun togglePanel() {
        if (expanded) collapsePanel() else expandPanel()
    }

    private fun expandPanel() {
        if (!Settings.canDrawOverlays(this)) return

        // Boot a headless Flutter engine running the overlay entrypoint
        if (engine == null) {
            val appBundlePath = io.flutter.FlutterInjector.instance()
                .flutterLoader().findAppBundlePath()
            engine = FlutterEngineGroup(this).createAndRunEngine(
                DartExecutor.DartEntrypoint(appBundlePath, OVERLAY_ENTRYPOINT)
            )
            methodChannel = MethodChannel(engine!!.dartExecutor.binaryMessenger, CHANNEL_FLUTTER)
            methodChannel!!.setMethodCallHandler { call, result ->
                when (call.method) {
                    "minimize" -> { collapsePanel(); result.success(true) }
                    "close" -> { stopSelf(); result.success(true) }
                    else -> result.notImplemented()
                }
            }
        }

        val flutterView = FlutterView(this)
        flutterView.attachToFlutterEngine(engine!!)

        val params = WindowManager.LayoutParams(
            (resources.displayMetrics.widthPixels * 0.92f).toInt(),
            (resources.displayMetrics.heightPixels * 0.68f).toInt(),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }

        windowManager.addView(flutterView, params)
        panelView = flutterView
        bubbleView?.visibility = View.GONE
        expanded = true
    }

    private fun collapsePanel() {
        panelView?.let { windowManager.removeView(it) }
        panelView = null
        bubbleView?.visibility = View.VISIBLE
        expanded = false
    }
}
