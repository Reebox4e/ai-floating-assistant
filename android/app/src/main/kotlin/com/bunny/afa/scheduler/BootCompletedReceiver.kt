package com.bunny.afa.scheduler

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-arms exact alarms after reboot. WorkManager already persists periodic
 * work across reboots; this receiver exists for AlarmManager-based exact
 * schedules (kept minimal for boilerplate).
 */
class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        // TODO: re-register exact alarms from the encrypted DB schedule table.
    }
}
