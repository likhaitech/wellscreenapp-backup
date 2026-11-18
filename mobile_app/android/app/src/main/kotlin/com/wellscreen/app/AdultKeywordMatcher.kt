package com.wellscreen.app

import java.util.Locale

/**
 * Native copy of lib/services/adult_keyword_detector.dart, used by
 * SiteBlocker to BLOCK adult domains that are not in the bundled dataset.
 * The Dart class only labels the browsing log; this one enforces.
 *
 * Same keywords and known-safe list as the Dart class (keep them in sync).
 * One deliberate difference: a known-safe entry also covers its
 * subdomains (www.youtube.com, music.youtube.com), because blocking the
 * real YouTube on a "tube" substring would be far worse here than a wrong
 * label in a report.
 *
 * Guardian "allow" rules are checked before this in SiteBlocker, so a
 * parent can always unblock a false positive.
 */
object AdultKeywordMatcher {
    private val KEYWORDS = listOf("porn", "xxx", "sex", "tube", "xvideos")

    private val KNOWN_SAFE_DOMAINS = setOf(
        "youtube.com",
        "youtube-nocookie.com",
        "youtu.be",
        "youtubekids.com",
        "roblox.com",
        "xbox.com",
        "x.com",
        "box.com",
        "dropbox.com",
        "fedex.com",
        "xfinity.com",
        "complex.com",
        "flexport.com",
        "nexus.com",
        "plexus.com",
        "context.com",
        "tubemogul.com",
        "essex.ac.uk",
        "essexpolice.uk",
        "middlesex.gov.uk",
        "sussex.ac.uk",
        "wessex.com",
        "oxford.ac.uk",
        "sexpistols-official.com",
    )

    private fun isKnownSafe(domain: String): Boolean {
        val labels = domain.split('.')
        for (start in 0..(labels.size - 2)) {
            val candidate = labels.subList(start, labels.size).joinToString(".")
            if (candidate in KNOWN_SAFE_DOMAINS) return true
        }
        return false
    }

    fun matches(domain: String): Boolean {
        val normalized = domain.trim().lowercase(Locale.ROOT).trimEnd('.')
        if (normalized.isEmpty()) return false
        if (isKnownSafe(normalized)) return false
        return KEYWORDS.any { normalized.contains(it) }
    }
}
