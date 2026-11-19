package com.wellscreen.app

/**
 * Popular apps whose "Lite" versions and websites give the same content.
 * When a guardian blocks one package of a group, every package and website
 * of that group is blocked too, so blocking TikTok also blocks TikTok Lite
 * and tiktok.com in the browser. Pure (no Android types) for unit tests.
 *
 * Only permanent blocks use this; daily time limits stay per app.
 */
internal object RelatedTargets {

    internal data class Group(val packages: Set<String>, val domains: Set<String>)

    internal val groups: List<Group> = listOf(
        Group(
            setOf("com.zhiliaoapp.musically", "com.ss.android.ugc.trill", "com.zhiliaoapp.musically.go"),
            setOf("tiktok.com"),
        ),
        Group(
            setOf("com.facebook.katana", "com.facebook.lite"),
            setOf("facebook.com", "fb.com", "fb.watch"),
        ),
        Group(
            setOf("com.facebook.orca", "com.facebook.mlite"),
            setOf("messenger.com"),
        ),
        Group(
            setOf("com.instagram.android", "com.instagram.lite"),
            setOf("instagram.com"),
        ),
        Group(
            setOf("com.google.android.youtube"),
            setOf("youtube.com", "youtu.be"),
        ),
        Group(
            setOf("com.twitter.android", "com.twitter.android.lite"),
            setOf("twitter.com", "x.com"),
        ),
        Group(setOf("com.roblox.client"), setOf("roblox.com")),
        Group(setOf("com.snapchat.android"), setOf("snapchat.com")),
        Group(setOf("com.discord"), setOf("discord.com", "discord.gg", "discordapp.com")),
        Group(setOf("com.reddit.frontpage"), setOf("reddit.com", "redd.it")),
        Group(setOf("tv.twitch.android.app"), setOf("twitch.tv")),
    )

    /**
     * The blocked package that covers [packageName]: itself when it is
     * blocked, otherwise a blocked package from the same group. Null when
     * nothing covers it.
     */
    fun blockingPackageFor(packageName: String, restricted: Set<String>): String? {
        if (packageName in restricted) return packageName
        val group = groups.firstOrNull { packageName in it.packages } ?: return null
        return group.packages.firstOrNull { it in restricted }
    }

    /** Other packages of the same app (TikTok -> TikTok Lite). */
    fun siblingsOf(packageName: String): Set<String> {
        val group = groups.firstOrNull { packageName in it.packages } ?: return emptySet()
        return group.packages - packageName
    }

    /** Packages that have websites in this list. */
    fun hasWebsites(packageName: String): Boolean =
        groups.any { packageName in it.packages && it.domains.isNotEmpty() }

    /** Websites to block because their app (or a sibling) is blocked. */
    fun domainsFor(restricted: Set<String>): Set<String> {
        if (restricted.isEmpty()) return emptySet()
        return groups
            .filter { group -> group.packages.any { it in restricted } }
            .flatMapTo(HashSet()) { it.domains }
    }
}
