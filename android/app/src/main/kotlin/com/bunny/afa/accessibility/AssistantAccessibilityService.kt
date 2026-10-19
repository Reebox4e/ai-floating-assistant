package com.bunny.afa.accessibility

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * MODULE 2 — Accessibility Service + Node Parser + Record & Replay
 *
 * • Parses the AccessibilityNodeInfo tree into stable "pathway" JSON so
 *   nodes survive re-layouts (viewIdResourceName + text + class + depth).
 * • RECORD: captures user clicks / text inputs into a replayable macro.
 * • REPLAY: locates nodes by pathway and performs CLICK / SET_TEXT on them —
 *   enabling automation inside WhatsApp, SMS, Calls and any other app.
 *
 * Bridges:
 *   MethodChannel "afa/automation"         → commands
 *   EventChannel  "afa/automation_events"  → recorded steps streamed to Dart
 */
class AssistantAccessibilityService : AccessibilityService() {

    companion object {
        var instance: AssistantAccessibilityService? = null
        var eventSink: EventChannel.EventSink? = null

        const val METHOD_CHANNEL = "afa/automation"
        const val EVENT_CHANNEL = "afa/automation_events"

        /** Registers channels from MainActivity (called on app start). */
        fun registerChannels(messenger: BinaryMessenger) {
            MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
                val svc = instance
                if (svc == null) {
                    result.error("SERVICE_OFF", "Accessibility service not connected", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "isConnected" -> result.success(true)
                    "recordStart" -> { svc.startRecording(); result.success(true) }
                    "recordStop" -> { svc.stopRecording(); result.success(svc.recordedStepsJson()) }
                    "replay" -> {
                        svc.replayMacro(call.argument<String>("stepsJson") ?: "[]")
                        result.success(true)
                    }
                    "inspect" -> result.success(svc.dumpRootTree().toString())
                    else -> result.notImplemented()
                }
            }
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

    @Volatile private var isRecording = false
    private var steps = JSONArray()

    // ───────────────────────── Service lifecycle ─────────────────────────

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        serviceInfo = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_VIEW_CLICKED or
                    AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED or
                    AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            notificationTimeout = 100
        }
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onInterrupt() {}

    // ───────────────────────── RECORDER ─────────────────────────

    fun startRecording() {
        synchronized(this) { steps = JSONArray() }
        isRecording = true
    }

    fun stopRecording() { isRecording = false }

    fun recordedStepsJson(): String = synchronized(this) { steps.toString() }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        if (!isRecording) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_VIEW_CLICKED -> {
                val node = event.source ?: return
                addStep("CLICK", node, event.packageName?.toString(), event.className?.toString())
            }
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> {
                val node = event.source ?: return
                val latest = event.text.lastOrNull()?.toString() ?: ""
                addStep("SET_TEXT", node, event.packageName?.toString(),
                    event.className?.toString()) { put("value", latest) }
            }
        }
    }

    private fun addStep(
        action: String,
        node: AccessibilityNodeInfo,
        pkg: String?,
        cls: String?,
        extra: JSONObject.() -> Unit = {}
    ) {
        val step = JSONObject().apply {
            put("action", action)
            put("package", pkg ?: "")
            put("class", cls ?: "")
            put("pathway", JSONArray(pathwayOf(node)))
            put("bounds", rectOf(node))
            put("viewId", node.viewIdResourceName ?: "")
            put("text", node.text?.toString() ?: "")
            extra()
        }
        synchronized(this) { steps.put(step) }
        eventSink?.success(step.toString())
    }

    // ───────────────────────── NODE PARSER ─────────────────────────

    /** Resilient pathway of hints from root → node. */
    private fun pathwayOf(node: AccessibilityNodeInfo): List<String> {
        val hops = mutableListOf<AccessibilityNodeInfo>()
        var cur: AccessibilityNodeInfo? = node
        while (cur != null) {
            hops += cur
            cur = try { cur.parent } catch (e: Exception) { null }
        }
        hops.reverse()
        return hops.drop(1).mapIndexed { i, hop -> hopHint(hop, i) }
    }

    private fun hopHint(n: AccessibilityNodeInfo, index: Int): String {
        n.viewIdResourceName?.let { return "id:$it" }
        n.text?.toString()?.takeIf { it.isNotBlank() }?.let { return "text:$it" }
        n.contentDescription?.toString()?.takeIf { it.isNotBlank() }?.let { return "desc:$it" }
        return "cls:${n.className ?: "View"}#$index"
    }

    private fun rectOf(n: AccessibilityNodeInfo): String {
        val r = android.graphics.Rect()
        n.getBoundsInScreen(r)
        return "${r.left};${r.top};${r.right};${r.bottom}"
    }

    /** Full BFS dump of the active window (for the "inspect" dev command). */
    private fun dumpRootTree(): JSONArray {
        val root = rootInActiveWindow ?: return JSONArray()
        val out = JSONArray()
        val queue = ArrayDeque<Pair<AccessibilityNodeInfo, Int>>()
        queue.add(root to 0)
        while (queue.isNotEmpty()) {
            val (node, depth) = queue.removeFirst()
            out.put(JSONObject().apply {
                put("depth", depth)
                put("viewId", node.viewIdResourceName ?: "")
                put("text", node.text?.toString() ?: "")
                put("cls", node.className?.toString() ?: "")
                put("clickable", node.isClickable)
                put("editable", node.isEditable)
                put("bounds", rectOf(node))
            })
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it to depth + 1) }
            }
        }
        return out
    }

    // ───────────────────────── REPLAY ENGINE ─────────────────────────

    private fun replayMacro(stepsJson: String) {
        val arr = JSONArray(stepsJson)
        Thread {
            for (i in 0 until arr.length()) {
                val step = arr.getJSONObject(i)
                val pathway = step.optJSONArray("pathway") ?: continue
                val hints = mutableListOf<String>()
                for (j in 0 until pathway.length()) hints += pathway.getString(j)

                val root = rootInActiveWindow ?: continue
                val node = findNodeByHints(root, hints) ?: fallbackSearch(step) ?: continue

                when (step.optString("action")) {
                    "CLICK" -> {
                        var target = node
                        var guard = 0
                        while (!target.isClickable && target.parent != null && guard++ < 5) {
                            target = target.parent
                        }
                        target.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    }
                    "SET_TEXT" -> {
                        val args = android.os.Bundle()
                        args.putCharSequence(
                            AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                            step.optString("value")
                        )
                        node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                    }
                }
                Thread.sleep(700) // human-paced step delay
            }
        }.start()
    }

    private fun findNodeByHints(root: AccessibilityNodeInfo, hints: List<String>): AccessibilityNodeInfo? {
        var current: AccessibilityNodeInfo = root
        for (hint in hints) {
            val next = matchChild(current, hint) ?: return null
            current = next
        }
        return current
    }

    private fun matchChild(parent: AccessibilityNodeInfo, hint: String): AccessibilityNodeInfo? {
        val key = hint.substringAfter(":")
        for (i in 0 until parent.childCount) {
            val child = parent.getChild(i) ?: continue
            when {
                hint.startsWith("id:") && child.viewIdResourceName == key -> return child
                hint.startsWith("text:") && child.text?.toString() == key -> return child
                hint.startsWith("desc:") && child.contentDescription?.toString() == key -> return child
                hint.startsWith("cls:") &&
                        child.className?.toString() == key.substringBefore('#') -> return child
            }
        }
        // Wide-net fallback by global viewId
        if (hint.startsWith("id:")) {
            return rootInActiveWindow
                ?.findAccessibilityNodeInfosByViewId(key)
                ?.firstOrNull()
        }
        return null
    }

    private fun fallbackSearch(step: JSONObject): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        val text = step.optString("text")
        if (text.isNotBlank()) {
            root.findAccessibilityNodeInfosByText(text).firstOrNull()?.let { return it }
        }
        return null
    }
}
