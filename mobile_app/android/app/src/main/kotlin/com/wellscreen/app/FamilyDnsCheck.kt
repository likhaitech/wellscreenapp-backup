package com.wellscreen.app

import android.util.Base64
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale

/**
 * Asks Cloudflare for Families (free, no account) whether it would refuse a
 * site: its family resolver answers 0.0.0.0 for adult and malware sites.
 * Only the site's address is sent - never page content or anything personal.
 *
 * Used ONLY for sites our own checks didn't decide, and its answer is only a
 * HINT: on its own it never blocks (except for the youngest age group); the
 * guardian is asked to review instead. Cloudflare's adult filter has
 * over-blocked some LGBT and sex-education sites in the past, which is why.
 *
 * Offline or slow (short timeout) means "no answer", never "block".
 * Answers are cached per domain so a site is asked about at most once every
 * few hours. The wire-format request (RFC 8484 DNS-over-HTTPS GET) avoids
 * depending on a JSON flavour of the API.
 */
object FamilyDnsCheck {
    const val ENDPOINT = "https://family.cloudflare-dns.com/dns-query"
    private const val TIMEOUT_MS = 2_500
    private const val CACHE_MS = 6 * 60 * 60 * 1000L
    private const val MAX_CACHE = 300

    enum class Verdict { ALLOWED, REFUSED, UNKNOWN }

    private data class Cached(val verdict: Verdict, val atMs: Long)

    private val cache = LinkedHashMap<String, Cached>()
    private val inFlight = HashSet<String>()

    /** DNS query for an A record of [domain] (RFC 1035 wire format). */
    internal fun buildQuery(domain: String): ByteArray {
        val out = ByteArrayOutputStream()
        // ID 0 (recommended for DoH caching), flags: recursion desired.
        out.write(byteArrayOf(0, 0, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0))
        for (label in domain.trimEnd('.').split('.')) {
            val bytes = label.toByteArray(Charsets.US_ASCII)
            require(bytes.isNotEmpty() && bytes.size <= 63) { "bad label" }
            out.write(bytes.size)
            out.write(bytes)
        }
        out.write(0)
        out.write(byteArrayOf(0, 1, 0, 1)) // type A, class IN
        return out.toByteArray()
    }

    private fun u16(b: ByteArray, i: Int): Int =
        ((b[i].toInt() and 0xff) shl 8) or (b[i + 1].toInt() and 0xff)

    /** Skips a (possibly compressed) name starting at [start]; returns the next index. */
    private fun skipName(b: ByteArray, start: Int): Int {
        var i = start
        while (true) {
            val len = b[i].toInt() and 0xff
            if (len == 0) return i + 1
            if (len and 0xc0 == 0xc0) return i + 2
            i += len + 1
        }
    }

    /**
     * REFUSED when an A answer is 0.0.0.0 (Cloudflare's "blocked" answer),
     * ALLOWED when there are other A answers, UNKNOWN otherwise (no answer,
     * NXDOMAIN, malformed).
     */
    internal fun parseVerdict(b: ByteArray): Verdict {
        return try {
            if (b.size < 12) return Verdict.UNKNOWN
            val qd = u16(b, 4)
            val an = u16(b, 6)
            var i = 12
            repeat(qd) { i = skipName(b, i) + 4 }
            var sawA = false
            repeat(an) {
                i = skipName(b, i)
                val type = u16(b, i)
                val rdLen = u16(b, i + 8)
                val rd = i + 10
                if (type == 1 && rdLen == 4) {
                    sawA = true
                    if (b[rd].toInt() == 0 && b[rd + 1].toInt() == 0 &&
                        b[rd + 2].toInt() == 0 && b[rd + 3].toInt() == 0) {
                        return Verdict.REFUSED
                    }
                }
                i = rd + rdLen
            }
            if (sawA) Verdict.ALLOWED else Verdict.UNKNOWN
        } catch (_: Exception) {
            Verdict.UNKNOWN
        }
    }

    /** The cached verdict, or null when the site hasn't been asked about recently. */
    fun cached(domain: String, nowMs: Long = System.currentTimeMillis()): Verdict? = synchronized(cache) {
        val key = domain.lowercase(Locale.ROOT)
        val hit = cache[key] ?: return null
        if (nowMs - hit.atMs > CACHE_MS) {
            cache.remove(key)
            return null
        }
        hit.verdict
    }

    internal fun remember(domain: String, verdict: Verdict, nowMs: Long = System.currentTimeMillis()) = synchronized(cache) {
        cache[domain.lowercase(Locale.ROOT)] = Cached(verdict, nowMs)
        while (cache.size > MAX_CACHE) cache.remove(cache.keys.first())
    }

    /**
     * Asks Cloudflare on a background thread and calls [onResult] there.
     * Does nothing when an answer is cached or a question is already out.
     * UNKNOWN answers (offline, timeout) are cached briefly too, so a phone
     * without internet doesn't retry on every page update.
     */
    fun checkAsync(domain: String, onResult: (Verdict) -> Unit) {
        val key = domain.lowercase(Locale.ROOT)
        if (cached(key) != null) return
        synchronized(inFlight) { if (!inFlight.add(key)) return }
        Thread {
            val verdict = try {
                ask(key)
            } catch (_: Exception) {
                Verdict.UNKNOWN
            } finally {
                synchronized(inFlight) { inFlight.remove(key) }
            }
            // Offline/unknown: remember for 5 minutes only.
            val at = if (verdict == Verdict.UNKNOWN) {
                System.currentTimeMillis() - CACHE_MS + 5 * 60 * 1000L
            } else {
                System.currentTimeMillis()
            }
            remember(key, verdict, at)
            try { onResult(verdict) } catch (_: Exception) { }
        }.start()
    }

    private fun ask(domain: String): Verdict {
        val query = Base64.encodeToString(
            buildQuery(domain),
            Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
        )
        val connection = URL("$ENDPOINT?dns=$query").openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.setRequestProperty("Accept", "application/dns-message")
            if (connection.responseCode != 200) return Verdict.UNKNOWN
            val body = connection.inputStream.use { it.readBytes() }
            return parseVerdict(body)
        } finally {
            connection.disconnect()
        }
    }
}
