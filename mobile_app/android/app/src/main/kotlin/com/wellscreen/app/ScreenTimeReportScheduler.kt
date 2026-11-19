package com.wellscreen.app

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.util.Log

/** Schedules a best-effort native catch-up sync, minimum 15-minute interval. */
internal object ScreenTimeReportScheduler {
    const val JOB_ID = 849113
    private const val TAG = "WellScreenBackground"
    private const val MIN_INTERVAL_MS = 15L * 60_000L

    fun schedule(context: Context) {
        val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE)
            as? JobScheduler ?: return
        val existingJob = scheduler.allPendingJobs.firstOrNull { it.id == JOB_ID }
        if (existingJob?.isPersisted == true) return
        if (existingJob != null) scheduler.cancel(JOB_ID)
        val job = JobInfo.Builder(
            JOB_ID,
            ComponentName(context, ScreenTimeReportJobService::class.java),
        )
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setPeriodic(MIN_INTERVAL_MS)
            .setPersisted(true)
            .build()
        if (scheduler.schedule(job) != JobScheduler.RESULT_SUCCESS) {
            Log.w(TAG, "Could not schedule native usage/limit catch-up")
        }
    }
}
