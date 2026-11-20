package com.wellscreen.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PageTextClassifierTest {
    private fun level(vararg texts: String) = PageTextClassifier.classify(texts.toList()).level

    @Test
    fun gamblingSiteWithInnocentNameIsBlockedByItsButtons() {
        val r = PageTextClassifier.classify(listOf(
            "Best Games Online", "Login", "Register",
            "Deposit bonus 100%", "Free spins every day", "Place your bet",
            "Withdraw", "Jackpot",
        ))
        assertEquals(PageTextClassifier.Level.BLOCK, r.level)
        assertEquals("gambling", r.category)
    }

    @Test
    fun philippineGamblingPageIsBlocked() {
        assertEquals(
            PageTextClassifier.Level.BLOCK,
            level("Deposit via GCash", "Minimum bet ₱10", "Online sabong", "Taya na!", "Withdraw"),
        )
    }

    @Test
    fun singleEverydayWordsNeverBlockAlone() {
        for (word in listOf("Deposit", "Spin the wheel!", "Odds and ends", "Bonus points", "Cash out")) {
            assertEquals(word, PageTextClassifier.Level.NONE, level(word))
        }
    }

    @Test
    fun bankAndEWalletPagesAreNotBlocked() {
        assertEquals(
            PageTextClassifier.Level.NONE,
            level("Cash in", "Cash out", "Deposit", "Withdraw", "Send money", "Pay bills", "Bonus rewards"),
        )
    }

    @Test
    fun newsStoryAboutGamblingIsNeverBlocked() {
        val r = PageTextClassifier.classify(listOf(
            "Senate probes online casino operators",
            "Sports betting and online sabong were discussed, along with slot machines, poker and odds.",
        ))
        assertEquals(true, r.level != PageTextClassifier.Level.BLOCK)
    }

    @Test
    fun explicitAdultPageIsBlocked() {
        val r = PageTextClassifier.classify(listOf("Free porn", "XXX videos", "Hot sex", "nude"))
        assertEquals(PageTextClassifier.Level.BLOCK, r.level)
        assertEquals("adult", r.category)
    }

    @Test
    fun topicWordsNeverCount() {
        val r = PageTextClassifier.classify(listOf(
            "Sex education for teens", "Puberty and consent", "LGBT support resources",
            "Gay and lesbian youth", "Gender identity", "Reproductive health", "HIV testing",
            "Safe sex", "Sexual health",
        ))
        assertEquals(PageTextClassifier.Level.NONE, r.level)
        assertNull(r.category)
        assertEquals(0, r.score)
    }

    @Test
    fun lookAlikeSpellingsAreCaught() {
        assertEquals(
            PageTextClassifier.Level.BLOCK,
            level("D3posit b0nus", "Fr33 sp1ns", "Pl4ce your b3t", "W1thdraw"),
        )
    }

    @Test
    fun wordsInsideOtherWordsDontCount() {
        // "bet" in "alphabet"/"better", "slot" in "slotted", "porn" in "pornography" study text.
        assertEquals(PageTextClassifier.Level.NONE, level("The alphabet is better slotted here"))
    }

    @Test
    fun repeatedWordCountsOnce() {
        assertEquals(PageTextClassifier.Level.NONE, level("bet bet bet bet bet bet bet bet bet"))
    }

    @Test
    fun oneActionPhraseIsOnlyAHint() {
        assertEquals(PageTextClassifier.Level.HINT, level("Claim your bonus", "deposit"))
    }

    @Test
    fun pureNumbersStayNumbers() {
        assertEquals("777", PageTextClassifier.normalizeToken("777"))
        assertEquals("casino", PageTextClassifier.normalizeToken("c4sino"))
    }

    @Test
    fun gamblingLobbyBeforeLoginIsBlockedByManyGameWords() {
        // Real PH sites show their game menu before login (no "deposit bonus" yet).
        val r = PageTextClassifier.classify(listOf(
            "Login/Register", "Recommended", "Tongits Joker", "Pusoy", "Slots",
            "Poker", "Baccarat", "Roulette", "Live Casino",
        ))
        assertEquals(PageTextClassifier.Level.BLOCK, r.level)
        assertEquals("gambling", r.category)
    }

    @Test
    fun fiveGamblingWordsWithoutActionIsNotBlocked() {
        // Like the encyclopedia article on gambling (the highest real
        // education page measured): stays below the strong-words bar.
        val r = PageTextClassifier.classify(listOf(
            "Gambling is wagering money. Bets on a casino slot or poker hand; the jackpot is rare.",
        ))
        assertEquals(true, r.level != PageTextClassifier.Level.BLOCK)
    }

    @Test
    fun adultTubeWithoutActionPhraseIsBlocked() {
        val r = PageTextClassifier.classify(listOf(
            "Home", "Categories", "Blowjob", "Milf", "Creampie", "Gangbang", "Threesome",
        ))
        assertEquals(PageTextClassifier.Level.BLOCK, r.level)
        assertEquals("adult", r.category)
    }

    @Test
    fun encyclopediaArticleAboutPornographyIsNotBlocked() {
        val r = PageTextClassifier.classify(listOf(
            "Pornography (often shortened to porn or porno) is the portrayal of sexual subject matter.",
            "Terms such as xxx and erotic art are discussed.",
        ))
        assertEquals(true, r.level != PageTextClassifier.Level.BLOCK)
    }

    @Test
    fun filipinoAdultPageIsBlocked() {
        // Like Tagalog adult sites (titles in Filipino, few English words).
        val r = PageTextClassifier.classify(listOf(
            "Pinay Scandal", "Bagong kantutan", "Iyot sa probinsya", "Jakol",
            "Malibog na misis", "Tamod", "Home", "Latest",
        ))
        assertEquals(PageTextClassifier.Level.BLOCK, r.level)
        assertEquals("adult", r.category)
    }

    @Test
    fun filipinoSexEducationPageIsNotBlocked() {
        val r = PageTextClassifier.classify(listOf(
            "Edukasyong pangkalusugan: pagdadalaga at pagbibinata",
            "Ang ari ng babae at lalaki, regla, at ligtas na pakikipagtalik",
            "Pag-iwas sa HIV at teenage pregnancy. Magtanong sa magulang o guro.",
        ))
        assertEquals(PageTextClassifier.Level.NONE, r.level)
    }

    @Test
    fun oneFilipinoWordAloneDoesNotBlock() {
        assertEquals(PageTextClassifier.Level.NONE, level("Chupa Chups lollipop", "Candy shop"))
    }

    @Test
    fun tubeSiteCategoryMenuIsBlocked() {
        // Like rbreezy.xyz in emulator testing: only a category list shows.
        val r = PageTextClassifier.classify(listOf(
            "Categories", "Amateur", "Anal", "Asian", "Big Boobs", "Blowjob",
            "Busty", "Hardcore", "Lesbian", "Teen",
        ))
        assertEquals(PageTextClassifier.Level.BLOCK, r.level)
        assertEquals("adult", r.category)
    }

    @Test
    fun healthPageWithOneClinicalWordIsNotBlocked() {
        val r = PageTextClassifier.classify(listOf(
            "Anal fissure: symptoms and treatment",
            "Breast and testicle self-checks for teens. Talk to a doctor.",
        ))
        assertEquals(PageTextClassifier.Level.NONE, r.level)
    }

    @Test
    fun twoExplicitWordsAreLabelledAdultButNotBlocked() {
        val r = PageTextClassifier.classify(listOf("Pinay Teen", "Viral", "Milf", "Creampie", "Latest videos"))
        assertEquals(PageTextClassifier.Level.LABEL, r.level)
        assertEquals("adult", r.category)
    }

    @Test
    fun oneExplicitWordIsNotLabelled() {
        assertEquals(PageTextClassifier.Level.NONE, level("Best cum laude graduates of 2026"))
    }
}
