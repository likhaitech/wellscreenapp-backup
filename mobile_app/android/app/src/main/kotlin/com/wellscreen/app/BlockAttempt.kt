package com.wellscreen.app

/**
 * One visit to a blocked site counts as ONE blocked attempt, even when the
 * browser reloads it several times (6 blocks in 0.3 s were seen in
 * testing). Re-blocks of the same site within [WINDOW_MS] are the same
 * attempt.
 */
internal object BlockAttempt {
    const val WINDOW_MS = 10_000L

    fun isSameAttempt(lastDomain: String?, lastTimeMs: Long, domain: String, nowMs: Long): Boolean =
        lastDomain == domain && nowMs - lastTimeMs < WINDOW_MS
}
