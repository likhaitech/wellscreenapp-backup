package com.wellscreen.app

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import java.util.concurrent.atomic.AtomicBoolean

internal object DeviceAdminAlertRetryPolicy {
    private const val MAX_AGE_MS = 24L * 60L * 60L * 1000L

    fun shouldRetry(savedAt: Long, now: Long): Boolean {
        return savedAt > 0L &&
            now >= savedAt &&
            now - savedAt < MAX_AGE_MS
    }

    fun shouldClear(
        currentTimestamp: Long,
        attemptedTimestamp: Long,
        delivered: Boolean
    ): Boolean {
        return delivered &&
            attemptedTimestamp > 0L &&
            currentTimestamp == attemptedTimestamp
    }
}

class DeviceAdminAlertRetryJobService : JobService() {

    companion object {
        private const val TAG = "DeviceAdminAlertRetry"
        private const val JOB_ID = 849114
        private const val PREFS = "FlutterSharedPreferences"
        private const val DISABLED_AT = "flutter.device_admin_disabled_at"
        private const val DISABLED_PROFILE =
            "flutter.device_admin_disabled_profile_id"
        private const val DISABLED_UID =
            "flutter.device_admin_disabled_child_uid"

        fun schedule(context: Context) {
            val prefs = context.getSharedPreferences(
                PREFS, Context.MODE_PRIVATE
            )

            val timestamp = prefs.getLong(DISABLED_AT, 0L)

            if (!DeviceAdminAlertRetryPolicy.shouldRetry(
                    timestamp, System.currentTimeMillis()
                )
            ) {
                return
            }

            val scheduler = context.getSystemService(
                Context.JOB_SCHEDULER_SERVICE
            ) as? JobScheduler ?: return

            // Preserve an existing retry job and its backoff.
            if (scheduler.allPendingJobs.any { it.id == JOB_ID }) return

            val job = JobInfo.Builder(
                JOB_ID,
                ComponentName(
                    context,
                    DeviceAdminAlertRetryJobService::class.java
                )
            )
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setMinimumLatency(60_000L)
                .setBackoffCriteria(
                    60_000L,
                    JobInfo.BACKOFF_POLICY_EXPONENTIAL
                )
                .build()

            if (scheduler.schedule(job) != JobScheduler.RESULT_SUCCESS) {
                Log.w(TAG, "Could not schedule Device Admin alert retry")
            }
        }

        fun cancel(context: Context) {
            val scheduler = context.getSystemService(
                Context.JOB_SCHEDULER_SERVICE
            ) as? JobScheduler ?: return

            scheduler.cancel(JOB_ID)
        }
    }

    private val stopped = AtomicBoolean(false)

    override fun onStartJob(params: JobParameters): Boolean {
        stopped.set(false)

        Thread {
            var needsRetry = false

            val prefs = getSharedPreferences(
                PREFS, Context.MODE_PRIVATE
            )

            try {
                val timestamp = prefs.getLong(DISABLED_AT, 0L)

                if (DeviceAdminAlertRetryPolicy.shouldRetry(
                        timestamp, System.currentTimeMillis()
                    )
                ) {
                    needsRetry = true

                    val profileId = prefs.getString(
                        DISABLED_PROFILE, null
                    )

                    val savedUid = prefs.getString(
                        DISABLED_UID, null
                    )

                    val user = runCatching {
                        FirebaseAuth.getInstance().currentUser
                    }.getOrNull()

                    if (!stopped.get() &&
                        user != null &&
                        !profileId.isNullOrBlank() &&
                        (savedUid.isNullOrBlank() || savedUid == user.uid) &&
                        prefs.getLong(DISABLED_AT, 0L) == timestamp
                    ) {
                        val delivered =
                            WellScreenDeviceAdminReceiver()
                                .notifyGuardian(
                                    prefs, user, profileId, timestamp
                                )

                        if (delivered) {
                            // The receiver clears the successfully delivered event.
                            // Retry only if another pending event remains.
                            needsRetry = DeviceAdminAlertRetryPolicy.shouldRetry(
                                prefs.getLong(DISABLED_AT, 0L),
                                System.currentTimeMillis()
                            )
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(
                    TAG,
                    "Retry failed: ${e.javaClass.simpleName}"
                )
                needsRetry = true
            } finally {
                if (!stopped.get()) {
                    val timestamp = prefs.getLong(DISABLED_AT, 0L)

                    jobFinished(
                        params,
                        needsRetry &&
                            DeviceAdminAlertRetryPolicy.shouldRetry(
                                timestamp, System.currentTimeMillis()
                            )
                    )
                }
            }
        }.start()

        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        stopped.set(true)

        val prefs = getSharedPreferences(
            PREFS, Context.MODE_PRIVATE
        )

        return DeviceAdminAlertRetryPolicy.shouldRetry(
            prefs.getLong(DISABLED_AT, 0L),
            System.currentTimeMillis()
        )
    }
}
