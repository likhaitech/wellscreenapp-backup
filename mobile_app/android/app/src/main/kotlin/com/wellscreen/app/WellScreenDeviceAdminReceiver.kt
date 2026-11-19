package com.wellscreen.app

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Source
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class WellScreenDeviceAdminReceiver : DeviceAdminReceiver() {

    companion object {
        private const val TAG = "WellScreenDeviceAdmin"
        private const val PREFS = "FlutterSharedPreferences"
        private const val ACTIVE_PROFILE = "flutter.active_child_profile_id"
        private const val BACKEND_URL = "flutter.backend_base_url"

        private const val DISABLED_AT = "flutter.device_admin_disabled_at"
        private const val DISABLED_PROFILE = "flutter.device_admin_disabled_profile_id"
        private const val DISABLED_UID = "flutter.device_admin_disabled_child_uid"

        internal val pendingLock = Any()
        private val deliveryLock = Any()
    }

    override fun onDisableRequested(
        context: Context,
        intent: Intent
    ): CharSequence {
        // The child opened the turn-off screen: tell the guardian right
        // away. Plain background thread, NOT goAsync(): DeviceAdminReceiver
        // writes this warning into the broadcast's result extras after we
        // return, which fails if the result was handed to goAsync().
        sendDisableAttemptAlert(context.applicationContext)
        return "Disabling WellScreen removes its uninstall protection. Please discuss this with your parent or guardian before continuing."
    }

    /** Best effort, one try, never blocks the warning dialog. */
    private fun sendDisableAttemptAlert(context: Context) {
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val profileId = prefs.getString(ACTIVE_PROFILE, null)
            val user = runCatching {
                FirebaseAuth.getInstance().currentUser
            }.getOrNull()
            if (user == null || profileId.isNullOrBlank()) return
            val timestamp = System.currentTimeMillis()

            Thread {
                try {
                    val sent = postAlert(
                        prefs, user, profileId, timestamp,
                        alertType = "device_admin_disable_attempt",
                        title = "WellScreen uninstall protection",
                        body = "Your child opened the screen to turn off " +
                            "uninstall protection.",
                    )
                    Log.i(TAG, if (sent) "Disable attempt alert sent" else "Disable attempt alert not sent")
                } catch (e: Exception) {
                    Log.w(TAG, "Disable attempt alert failed: ${e.javaClass.simpleName}")
                }
            }.start()
        } catch (e: Exception) {
            Log.w(TAG, "Unable to start disable attempt alert")
        }
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)

        val prefs = context.getSharedPreferences(
            PREFS, Context.MODE_PRIVATE
        )

        val timestamp = System.currentTimeMillis()
        val profileId = prefs.getString(ACTIVE_PROFILE, null)

        val user = runCatching {
            FirebaseAuth.getInstance().currentUser
        }.getOrNull()

        // Persist the event before attempting network delivery.
        val saved = synchronized(pendingLock) {
            prefs.edit()
                .putLong(DISABLED_AT, timestamp)
                .putString(DISABLED_PROFILE, profileId)
                .putString(DISABLED_UID, user?.uid)
                .commit()
        }

        if (saved) {
            Log.i(TAG, "Device Admin disabled timestamp saved")
            // Schedule a fallback before attempting immediate delivery.
            DeviceAdminAlertRetryJobService.schedule(context.applicationContext)
        } else {
            Log.w(TAG, "Unable to persist Device Admin disabled timestamp")
        }

        if (user == null || profileId.isNullOrBlank()) {
            Log.i(TAG, "Alert deferred: child account unavailable")
            DeviceAdminAlertRetryJobService.schedule(context.applicationContext)
            return
        }

        // Perform the network request outside the main thread.
        val pendingResult = goAsync()
        val finished = AtomicBoolean(false)
        val handler = Handler(Looper.getMainLooper())

        val finish = Runnable {
            if (finished.compareAndSet(false, true)) {
                pendingResult.finish()
            }
        }

        handler.postDelayed(finish, 8500L)

        try {
            Thread {
                try {
                    if (notifyGuardian(prefs, user, profileId, timestamp)) {
                        synchronized(pendingLock) {
                            if (prefs.getLong(DISABLED_AT, 0L) == timestamp) {
                                prefs.edit()
                                    .remove(DISABLED_AT)
                                    .remove(DISABLED_PROFILE)
                                    .remove(DISABLED_UID)
                                    .commit()
                            }
                        }

                        Log.i(TAG, "Device Admin disabled alert sent")
                    } else {
                        Log.i(TAG, "Alert deferred: notification not sent")
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Alert deferred: ${e.javaClass.simpleName}")
                } finally {
                    if (prefs.getLong(DISABLED_AT, 0L) == timestamp) {
                        DeviceAdminAlertRetryJobService.schedule(context.applicationContext)
                    }
                    handler.removeCallbacks(finish)
                    finish.run()
                }
            }.start()
        } catch (e: Exception) {
            handler.removeCallbacks(finish)
            finish.run()
            Log.w(TAG, "Alert deferred: unable to start background request")
            DeviceAdminAlertRetryJobService.schedule(context.applicationContext)
        }
    }

    internal fun notifyGuardian(
        prefs: SharedPreferences,
        user: FirebaseUser,
        profileId: String,
        timestamp: Long
    ): Boolean {
        synchronized(deliveryLock) {
            if (prefs.getLong(DISABLED_AT, 0L) != timestamp) return false

            val delivered = notifyGuardianLocked(prefs, user, profileId, timestamp)

            if (delivered) {
                synchronized(pendingLock) {
                    if (prefs.getLong(DISABLED_AT, 0L) == timestamp) {
                        prefs.edit()
                            .remove(DISABLED_AT)
                            .remove(DISABLED_PROFILE)
                            .remove(DISABLED_UID)
                            .commit()
                    }
                }
            }

            return delivered
        }
    }

    private fun notifyGuardianLocked(
        prefs: SharedPreferences,
        user: FirebaseUser,
        profileId: String,
        timestamp: Long
    ): Boolean = postAlert(
        prefs, user, profileId, timestamp,
        alertType = "device_admin_disabled",
        title = "WellScreen uninstall protection disabled",
        body = "Device Admin protection has been disabled on your child's device.",
    )

    /** POST /alerts/notify for this paired child. True when the push was sent. */
    private fun postAlert(
        prefs: SharedPreferences,
        user: FirebaseUser,
        profileId: String,
        timestamp: Long,
        alertType: String,
        title: String,
        body: String,
    ): Boolean {
        val host = prefs.getString(BACKEND_URL, null)
            ?.trimEnd('/') ?: return false

        val endpoint = URL("$host/alerts/notify")

        if (endpoint.protocol != "https" || endpoint.userInfo != null) {
            return false
        }

        val tokenTask = user.getIdToken(false)

        val profileTask = FirebaseFirestore.getInstance()
            .collection("users")
            .document(user.uid)
            .get(Source.SERVER)

        Tasks.await(
            Tasks.whenAll(tokenTask, profileTask),
            3,
            TimeUnit.SECONDS
        )

        val token = tokenTask.result.token ?: return false
        val child = profileTask.result ?: return false

        val parentUid = child.getString("pairedParentId")
            ?: return false

        if (parentUid.isBlank() || parentUid == user.uid) {
            return false
        }

        if (child.getString("pairedChildProfileId") != profileId) {
            return false
        }

        if (FirebaseAuth.getInstance().currentUser?.uid != user.uid ||
            prefs.getString(ACTIVE_PROFILE, null) != profileId
        ) {
            return false
        }

        val payload = JSONObject()
            .put("parent_uid", parentUid)
            .put("title", title)
            .put("body", body)
            .put("alert_type", alertType)
            .put(
                "data",
                JSONObject()
                    .put("childProfileId", profileId)
                    .put("timestampMs", timestamp)
            )

        val connection = endpoint.openConnection() as HttpURLConnection

        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 2000
            connection.readTimeout = 3000
            connection.instanceFollowRedirects = false
            connection.doOutput = true

            connection.setRequestProperty(
                "Authorization", "Bearer $token"
            )

            connection.setRequestProperty(
                "Content-Type", "application/json"
            )

            connection.outputStream.use {
                it.write(payload.toString().toByteArray(Charsets.UTF_8))
            }

            if (connection.responseCode !in 200..299) {
                return false
            }

            val response = JSONObject(
                connection.inputStream.bufferedReader().use {
                    it.readText()
                }
            )

            return response.optString("status") == "sent"
        } finally {
            connection.disconnect()
        }
    }
}