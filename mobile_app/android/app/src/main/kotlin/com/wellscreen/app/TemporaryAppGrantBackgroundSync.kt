package com.wellscreen.app

import android.content.Context
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.QuerySnapshot
import com.google.firebase.firestore.Source
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * Best-effort native catch-up for server-approved, PACKAGE-SPECIFIC chat grants.
 *
 * This is called by ScreenTimeReportJobService on its worker thread after the
 * paired-child profile has already been verified against Firestore SERVER.
 * It never edits app_rules or the global emergency-access bypass.
 *
 * It must not run on the Android main thread: Firebase Tasks.await and HTTPS
 * calls below intentionally block a background worker until bounded timeouts.
 */
internal object TemporaryAppGrantBackgroundSync {
    private const val TAG = "WellScreenChatGrants"
    private const val PREFS = "FlutterSharedPreferences"
    private const val ACTIVE_CHILD = "flutter.active_child_profile_id"
    private const val GRANTS = "flutter.temporary_access_grants_json"
    private const val BACKEND = "flutter.backend_base_url"
    private const val MAX_DURATION_MS = 180L * 60_000L
    private const val TASK_TIMEOUT_SECONDS = 10L
    // Bound each background run so that grant activation cannot monopolize
    // the existing periodic usage-reporting job when many requests are queued.
    private const val MAX_ACTIVATIONS_PER_RUN = 3
    private val packageIdPattern = Regex("^[A-Za-z0-9_.-]{3,200}$")

    fun synchronize(context: Context, childProfileId: String, childUid: String): Boolean {
        if (childProfileId.isBlank() || childUid.isBlank()) return false
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!isCurrentChild(childUid, childProfileId, prefs.getString(ACTIVE_CHILD, null))) {
            return false
        }

        val collection = FirebaseFirestore.getInstance()
            .collection("child_profiles")
            .document(childProfileId)
            .collection("temporary_access_grants")
        try {
            // SERVER-only: never activate a cached/unconfirmed pending grant.
            var snapshot = Tasks.await(
                collection.get(Source.SERVER), TASK_TIMEOUT_SECONDS, TimeUnit.SECONDS,
            )
            val pending = snapshot.documents.asSequence()
                .filter { document ->
                    document.getString("state") == "pending_activation" &&
                        document.getString("packageName") == document.id &&
                        packageIdPattern.matches(document.id) &&
                        document.getString("childUid") == childUid
                }
                .map { it.id }
                .take(MAX_ACTIVATIONS_PER_RUN)
                .toList()

            if (pending.isNotEmpty()) {
                val backendBase = prefs.getString(BACKEND, null)?.trim()?.trimEnd('/')
                // Never send a Firebase ID token to an untrusted HTTP origin.
                if (backendBase != null && backendBase.startsWith("https://")) {
                    val currentUser = FirebaseAuth.getInstance().currentUser
                    val token = if (currentUser?.uid == childUid) {
                        try {
                            Tasks.await(
                                currentUser.getIdToken(false),
                                TASK_TIMEOUT_SECONDS, TimeUnit.SECONDS,
                            ).token
                        } catch (error: Exception) {
                            Log.w(TAG, "Could not retrieve child session for activation", error)
                            null
                        }
                    } else null
                    if (!token.isNullOrBlank()) {
                        for (pkg in pending) {
                            if (!isCurrentChild(childUid, childProfileId,
                                    prefs.getString(ACTIVE_CHILD, null))) {
                                return false
                            }
                            // The authenticated backend checks child pairing,
                            // pending state and expiry, then starts the clock once.
                            activateGrant(backendBase, childProfileId, pkg, token)
                        }
                        // Read SERVER again; never invent a local expiry from
                        // an HTTP response or from the requested duration.
                        snapshot = Tasks.await(
                            collection.get(Source.SERVER),
                            TASK_TIMEOUT_SECONDS, TimeUnit.SECONDS,
                        )
                    }
                } else {
                    Log.w(TAG, "Cannot activate pending grant: HTTPS backend URL not configured")
                }
            }

            val now = System.currentTimeMillis()
            val confirmed = activeGrants(snapshot, childUid, now)
            // Do not write a cache under another signed-in account/child.
            if (!isCurrentChild(childUid, childProfileId,
                    prefs.getString(ACTIVE_CHILD, null))) {
                return false
            }
            val serialized = JSONObject()
                .put("childProfileId", childProfileId)
                .put("grants", confirmed)
                .toString()
            val saved = prefs.edit().putString(GRANTS, serialized).commit()
            if (!saved) {
                Log.w(TAG, "Could not persist temporary grant cache")
                return false
            }
            Log.i(TAG, "Synchronized ${confirmed.length()} active temporary app grant(s)")
            return true
        } catch (error: Exception) {
            // Preserve the previous local cache on transient Firestore, token
            // or network failure. Native TemporaryAppGrantCache still rejects
            // every grant once its locally stored expiresAtMs passes.
            Log.w(TAG, "Temporary app grant sync deferred; old cache preserved", error)
            return false
        }
    }

    private fun isCurrentChild(childUid: String, childProfileId: String, cachedProfile: String?): Boolean =
        FirebaseAuth.getInstance().currentUser?.uid == childUid &&
            cachedProfile == childProfileId

    private fun activeGrants(
        snapshot: QuerySnapshot,
        childUid: String,
        nowMs: Long,
    ): JSONArray {
        val result = JSONArray()
        for (doc in snapshot.documents) {
            val pkg = doc.getString("packageName") ?: continue
            val until = doc.getTimestamp("expiresAt")?.toDate()?.time ?: continue
            if (pkg != doc.id || !packageIdPattern.matches(pkg) ||
                doc.getString("childUid") != childUid ||
                doc.getString("state") != "active" ||
                until <= nowMs || until - nowMs > MAX_DURATION_MS
            ) continue
            result.put(
                JSONObject()
                    .put("packageName", pkg)
                    .put("state", "active")
                    .put("expiresAtMs", until),
            )
        }
        return result
    }

    private fun activateGrant(baseUrl: String, childProfileId: String, pkg: String, token: String) {
        var connection: HttpURLConnection? = null
        try {
            // IDs are validated above; both path components are bounded to
            // one segment by the backend's own checks.
            val endpoint = URL("$baseUrl/chat/grants/$childProfileId/$pkg/activate")
            if (endpoint.protocol != "https") return
            val conn = endpoint.openConnection() as HttpURLConnection
            connection = conn
            conn.requestMethod = "POST"
            conn.connectTimeout = 5_000
            conn.readTimeout = 8_000
            conn.setRequestProperty("Authorization", "Bearer $token")
            conn.setRequestProperty("Accept", "application/json")
            val code = conn.responseCode
            if (code !in 200..299) {
                Log.w(TAG, "Grant activation deferred for $pkg: HTTP $code")
                return
            }
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            if (JSONObject(body).optString("status") != "active") {
                Log.w(TAG, "Grant activation for $pkg did not return active status")
            }
        } catch (error: Exception) {
            Log.w(TAG, "Grant activation deferred for $pkg", error)
        } finally {
            connection?.disconnect()
        }
    }
}
