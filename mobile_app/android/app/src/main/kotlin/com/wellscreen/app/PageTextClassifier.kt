package com.wellscreen.app

import java.util.Locale

/**
 * Page-word check: reads the words a browser is showing (title, headings,
 * buttons, visible text - collected by WellScreenAccessibilityService) and
 * decides whether the page is clearly a gambling or explicit adult page.
 *
 * Why it exists: a brand-new site with an innocent name gets past the
 * address checks (lists, keywords, gambling AI). Once the child is inside,
 * a gambling site still has to show what it does - Deposit, Withdraw, Bet,
 * Cash out - so the page itself gives it away.
 *
 * Rules (rule-based, NOT AI, no training data):
 * - Only EXPLICIT content counts. Topic words (LGBT, gay, gender, sex
 *   education, puberty, consent, reproductive health, HIV...) are never in
 *   these lists, so research and health pages are not blocked.
 * - A single everyday word (deposit, spin, odds, bonus) can never block on
 *   its own: words score 1, topic phrases 2, action phrases 3, and a block
 *   needs a minimum score, several different matches AND an action phrase
 *   ("deposit bonus", "place your bet", "free porn") - so a news story that
 *   only talks about gambling is not blocked.
 * - Each term counts once per page, however often it appears.
 * - Nothing is saved or sent: the text is scored and dropped.
 *
 * Pure Kotlin (no Android types) so it can be unit tested. The thresholds
 * were set by measuring real pages - see ml/page_text/README.md.
 */
object PageTextClassifier {

    enum class Level { NONE, HINT, BLOCK }

    data class Result(
        val level: Level,
        val category: String?, // "gambling" or "adult" when level != NONE
        val score: Int,
        val matches: List<String>,
    )

    /**
     * BLOCK: score >= [BLOCK_SCORE], at least [BLOCK_MIN_TERMS] different
     * terms, AND at least one action/explicit phrase (a page that only
     * TALKS about gambling, like a news story, has no "deposit bonus").
     */
    const val BLOCK_SCORE = 7
    const val BLOCK_MIN_TERMS = 3

    /**
     * HINT (guardian review, never a block on its own except for the
     * youngest age group): an action/explicit phrase with score >=
     * [HINT_SCORE], or any score >= [HINT_ANY_SCORE].
     */
    const val HINT_SCORE = 4
    const val HINT_ANY_SCORE = 6

    private const val ACTION = 3
    private const val TOPIC = 2
    private const val WORD = 1

    // Things only a betting site asks you to DO.
    private val GAMBLING_ACTIONS = listOf(
        "deposit bonus", "welcome bonus", "no deposit bonus", "claim bonus",
        "claim your bonus", "minimum bet", "min bet", "max bet",
        "place your bet", "place bet", "bet now", "withdraw winnings",
        "free spins", "spin now", "gcash deposit", "deposit via gcash",
        "deposit with gcash", "maya deposit", "deposit via maya",
        "deposit with maya", "taya na", "tumaya na",
    )

    // Gambling topics - a casino page has them, but so can a news story.
    private val GAMBLING_TOPICS = listOf(
        "online casino", "live casino", "casino games", "slot games",
        "slot machine", "slot machines", "sports betting", "betting odds",
        "e-sabong", "esabong", "online sabong", "sabong live", "pustahan",
        "lucky spin", "mega jackpot", "live dealer",
    )

    // Single words - common on normal sites too, so weak alone.
    private val GAMBLING_WORDS = listOf(
        "deposit", "withdraw", "withdrawal", "bet", "bets", "betting", "wager",
        "casino", "slots", "slot", "spin", "spins", "jackpot", "odds", "bonus",
        "poker", "baccarat", "roulette", "blackjack", "payout", "sportsbook",
        "cash out", "cashout", "taya", "pusta", "sugal", "sabong", "jueteng",
        "tongits", "pusoy",
    )

    // Explicit adult phrases.
    private val ADULT_ACTIONS = listOf(
        "free porn", "porn videos", "porn video", "sex videos", "sex video",
        "xxx videos", "xxx video", "hot sex", "nude pics", "nude photos",
        "naked girls", "adult videos", "hardcore sex", "live sex", "sex cams",
        "sex cam", "18+ videos", "watch porn", "porn tube", "full porn",
    )

    // Explicit adult words (never topic words - see the class comment).
    private val ADULT_WORDS = listOf(
        "porn", "porno", "pornhub", "xxx", "xnxx", "xvideos", "xhamster",
        "hentai", "nsfw", "blowjob", "cumshot", "creampie", "gangbang",
        "milf", "pussy", "fuck", "fucking", "horny", "nude", "nudes",
        "erotic", "fetish", "bdsm", "camgirl", "camgirls", "escort", "escorts",
        "stripper", "threesome", "orgy",
    )

    /**
     * Look-alike characters in a word that also has letters
     * ("c4sino", "p0rn", "s1ots"). Pure numbers ("777") stay as they are.
     */
    internal fun normalizeToken(token: String): String {
        if (token.none { it.isLetter() } || token.none { it.isDigit() || it == '@' || it == '$' }) {
            return token
        }
        val out = StringBuilder(token.length)
        for (c in token) {
            out.append(
                when (c) {
                    '0' -> 'o'; '1' -> 'i'; '3' -> 'e'; '4' -> 'a'
                    '5' -> 's'; '7' -> 't'; '@' -> 'a'; '$' -> 's'
                    else -> c
                }
            )
        }
        return out.toString()
    }

    /** Lowercase words, look-alikes fixed, joined by single spaces. */
    internal fun normalize(texts: List<String>): String {
        val tokens = ArrayList<String>()
        for (text in texts) {
            text.lowercase(Locale.ROOT)
                .split(Regex("[^\\p{L}\\p{N}@$+\\-]+"))
                .filter { it.isNotBlank() }
                .forEach { tokens.add(normalizeToken(it.trim('-'))) }
        }
        return " " + tokens.joinToString(" ") + " "
    }

    private fun containsTerm(text: String, term: String): Boolean =
        text.contains(" $term ")

    private data class Score(val total: Int, val matches: List<String>, val hasAction: Boolean)

    private fun score(
        text: String,
        actions: List<String>,
        topics: List<String>,
        words: List<String>,
    ): Score {
        var total = 0
        val matches = ArrayList<String>()
        var hasAction = false
        for (phrase in actions) {
            if (containsTerm(text, phrase)) {
                total += ACTION
                matches.add(phrase)
                hasAction = true
            }
        }
        for (phrase in topics) {
            if (containsTerm(text, phrase)) {
                total += TOPIC
                matches.add(phrase)
            }
        }
        for (word in words) {
            // A word inside a phrase already counted is not counted again.
            if (containsTerm(text, word) &&
                matches.none { " $it ".contains(" $word ") }) {
                total += WORD
                matches.add(word)
            }
        }
        return Score(total, matches, hasAction)
    }

    private fun levelFor(s: Score): Level = when {
        s.total >= BLOCK_SCORE && s.matches.size >= BLOCK_MIN_TERMS && s.hasAction -> Level.BLOCK
        (s.hasAction && s.total >= HINT_SCORE) || s.total >= HINT_ANY_SCORE -> Level.HINT
        else -> Level.NONE
    }

    fun classify(texts: List<String>): Result {
        val text = normalize(texts)
        val g = score(text, GAMBLING_ACTIONS, GAMBLING_TOPICS, GAMBLING_WORDS)
        val a = score(text, ADULT_ACTIONS, emptyList(), ADULT_WORDS)
        val gLevel = levelFor(g)
        val aLevel = levelFor(a)
        if (gLevel == Level.NONE && aLevel == Level.NONE) {
            return Result(Level.NONE, null, maxOf(g.total, a.total), emptyList())
        }
        // The stronger level wins; on a tie, the higher score.
        val gamblingWins = gLevel > aLevel || (gLevel == aLevel && g.total >= a.total)
        return if (gamblingWins) {
            Result(gLevel, "gambling", g.total, g.matches)
        } else {
            Result(aLevel, "adult", a.total, a.matches)
        }
    }
}
