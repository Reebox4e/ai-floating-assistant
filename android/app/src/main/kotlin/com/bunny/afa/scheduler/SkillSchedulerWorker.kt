package com.bunny.afa.scheduler

import android.content.Context
import androidx.work.*
import java.util.concurrent.TimeUnit

/**
 * MODULE 5 — Daily Schedules (WorkManager)
 *
 * Each skill (JSON macro) can be scheduled. The worker fires the
 * "afa/skill_due" broadcast which the app's background isolate
 * (or overlay service) picks up and replays via the accessibility engine.
 *
 * Dart side (workmanager package) registers callbacks; this class provides
 * the Kotlin-side helpers for re-scheduling after reboot.
 */
class SkillSchedulerWorker(appContext: Context, params: WorkerParameters) :
    CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val skillId = inputData.getString("skillId") ?: return Result.failure()
        val stepsJson = inputData.getString("stepsJson") ?: return Result.failure()

        // Hand the macro to the replay engine via broadcast; the
        // AssistantAccessibilityService (if connected) replays it.
        val intent = android.content.Intent(SkillSchedulerWorker.REPLAY_BROADCAST).apply {
            setPackage(applicationContext.packageName)
            putExtra("stepsJson", stepsJson)
            putExtra("skillId", skillId)
        }
        applicationContext.sendBroadcast(intent)
        return Result.success()
    }

    companion object {
        const val REPLAY_BROADCAST = "com.bunny.afa.REPLAY_SKILL"
        const val UNIQUE_PERIODIC = "afa_daily_skill_"

        /** Schedule a skill every day at a fixed delay from now (milliseconds). */
        fun scheduleDaily(context: Context, skillId: String, stepsJson: String, initialDelayMs: Long) {
            val request = PeriodicWorkRequestBuilder<SkillSchedulerWorker>(1, TimeUnit.DAYS)
                .setInitialDelay(initialDelayMs, TimeUnit.MILLISECONDS)
                .setInputData(
                    workDataOf(
                        "skillId" to skillId,
                        "stepsJson" to stepsJson
                    )
                )
                .setConstraints(
                    Constraints.Builder()
                        .setRequiresBatteryNotLow(true)
                        .build()
                )
                .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(UNIQUE_PERIODIC + skillId, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        /** One-shot scheduled routine (AlarmManager-style, deferrable). */
        fun scheduleOnce(context: Context, skillId: String, stepsJson: String, delayMs: Long) {
            val request = OneTimeWorkRequestBuilder<SkillSchedulerWorker>()
                .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
                .setInputData(workDataOf("skillId" to skillId, "stepsJson" to stepsJson))
                .build()
            WorkManager.getInstance(context)
                .enqueueUniqueWork("afa_once_$skillId", ExistingWorkPolicy.REPLACE, request)
        }

        fun cancel(context: Context, skillId: String) {
            WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_PERIODIC + skillId)
        }
    }
}
