package com.wellscreen.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NameCategoryModelTest {

    // Tiny two-class model: the letter pair "zz" pushes towards gambling.
    private fun model(threshold: Double = 0.9) = NameCategoryModel(
        minN = 2,
        maxN = 2,
        vocabIndex = mapOf("zz" to 0, "ok" to 1),
        idf = doubleArrayOf(1.0, 1.0),
        classes = listOf("gambling", "safe"),
        coefficients = arrayOf(doubleArrayOf(6.0, -6.0), doubleArrayOf(-6.0, 6.0)),
        intercepts = doubleArrayOf(0.0, 0.0),
        liveThreshold = threshold,
        liveClasses = setOf("gambling"),
    )

    @Test
    fun confidentGamblingMeetsTheBar() {
        val p = model().predict("zz.zz")!!
        assertEquals("gambling", p.category)
        assertTrue(p.confidence > 0.99)
        assertTrue(p.meetsDeploymentBar)
    }

    @Test
    fun safePredictionNeverMeetsTheBar() {
        val p = model().predict("ok.ok")!!
        assertEquals("safe", p.category)
        assertFalse(p.meetsDeploymentBar)
    }

    @Test
    fun lowConfidenceGamblingDoesNotMeetTheBar() {
        val p = model(threshold = 0.9999999).predict("zzok")!!
        assertFalse(p.meetsDeploymentBar)
    }

    @Test
    fun unknownLettersGiveNoPrediction() {
        assertNull(model().predict("abc"))
    }

    @Test
    fun knownNormalSitesAreNeverTreatedAsGambling() {
        assertTrue(GamblingNameClassifier.isKnownNotGambling("casio.com"))
        assertTrue(GamblingNameClassifier.isKnownNotGambling("www.casio.com"))
        assertTrue(GamblingNameClassifier.isKnownNotGambling("begambleaware.org"))
        assertFalse(GamblingNameClassifier.isKnownNotGambling("okbet.com"))
    }
}
