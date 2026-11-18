package com.wellscreen.app

import kotlin.math.exp
import kotlin.math.sqrt

/**
 * Native copy of lib/services/site_category_ml_classifier.dart: the trained
 * website-category model (TF-IDF character n-grams + logistic regression,
 * ml/site_category/train_category_classifier.py). Same weights file, same
 * maths, so the phone's blocker and the parent's report agree.
 *
 * Pure Kotlin (no Android types) so it can be unit tested on the JVM.
 */
class NameCategoryModel(
    private val minN: Int,
    private val maxN: Int,
    private val vocabIndex: Map<String, Int>,
    private val idf: DoubleArray,
    private val classes: List<String>,
    private val coefficients: Array<DoubleArray>,
    private val intercepts: DoubleArray,
    private val liveThreshold: Double,
    private val liveClasses: Set<String>,
) {
    data class Prediction(
        val category: String,
        val confidence: Double,
        val meetsDeploymentBar: Boolean,
    )

    fun predict(domain: String): Prediction? {
        val text = domain.lowercase()
        val counts = HashMap<Int, Int>()
        for (n in minN..maxN) {
            if (text.length < n) continue
            for (i in 0..text.length - n) {
                val idx = vocabIndex[text.substring(i, i + n)] ?: continue
                counts[idx] = (counts[idx] ?: 0) + 1
            }
        }
        if (counts.isEmpty()) return null

        val tfidf = HashMap<Int, Double>(counts.size)
        var sumSquares = 0.0
        for ((idx, count) in counts) {
            val value = count * idf[idx]
            tfidf[idx] = value
            sumSquares += value * value
        }
        val norm = sqrt(sumSquares)
        if (norm == 0.0) return null

        val scores = DoubleArray(classes.size) { c ->
            var score = intercepts[c]
            val weights = coefficients[c]
            for ((idx, value) in tfidf) score += weights[idx] * (value / norm)
            score
        }
        val maxScore = scores.max()
        val expScores = scores.map { exp(it - maxScore) }
        val sumExp = expScores.sum()
        var best = 0
        for (i in 1 until expScores.size) {
            if (expScores[i] > expScores[best]) best = i
        }
        val category = classes[best]
        val confidence = expScores[best] / sumExp
        return Prediction(
            category,
            confidence,
            category in liveClasses && confidence >= liveThreshold,
        )
    }
}
