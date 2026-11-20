package com.wellscreen.app

/**
 * Search engines and big platforms where the page-word check must NOT run.
 *
 * Why: the page check blocks a whole SITE (the domain). On a search engine
 * or a big platform, one page can show explicit words - e.g. Google results
 * after searching an adult site's name - and the check would then block
 * google.com itself for an hour. Found in emulator testing, 21 Nov 2026.
 *
 * These sites are still covered by the guardian's own Block rule, and the
 * optional family Private DNS (family.cloudflare-dns.com) forces SafeSearch
 * on Google, Bing and YouTube. Address checks are not affected.
 */
object PageCheckExempt {
    // Matched as the whole site name or a parent of it (www.google.com,
    // m.youtube.com). For Google, any country ending (google.com.ph).
    private val DOMAINS = setOf(
        "bing.com", "duckduckgo.com", "yahoo.com", "ecosia.org",
        "search.brave.com", "startpage.com", "baidu.com", "yandex.com",
        "youtube.com", "youtu.be", "facebook.com", "messenger.com",
        "instagram.com", "tiktok.com", "x.com", "twitter.com",
        "reddit.com", "pinterest.com",
    )

    fun isExempt(domain: String): Boolean {
        var d = domain.trim().lowercase().trimEnd('.')
        if (d.startsWith("www.")) d = d.removePrefix("www.")
        if (d.isEmpty()) return false
        val labels = d.split('.')
        // google.com, google.com.ph, google.co.uk, news.google.com ...
        val g = labels.indexOf("google")
        if (g >= 0 && labels.size - g in 2..3 && labels.drop(g + 1).all { it.length <= 3 }) {
            return true
        }
        for (start in 0..(labels.size - 2)) {
            if (labels.subList(start, labels.size).joinToString(".") in DOMAINS) return true
        }
        return false
    }
}
