package com.wellscreen.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Blocks NEW gambling websites that are not in the bundled list, using the
 * trained name model (NameCategoryModel). It only acts when the model says
 * "gambling" with at least the deployment confidence stored in the weights
 * file (0.90). At that bar the model wrongly flagged 1 of 200 unseen normal
 * websites in evaluation (ml/site_category/output/
 * category_classifier_evaluation.txt). Guardian "allow" rules are checked
 * before this in SiteBlocker, so a parent can always undo a mistake.
 */
object GamblingNameClassifier {
    private const val ASSET =
        "flutter_assets/assets/site_categories/category_classifier_weights.json"

    @Volatile private var model: NameCategoryModel? = null
    @Volatile private var loadFailed = false

    /**
     * Popular normal websites the model scores as gambling (found by running
     * it over DNSFilter's top 250,000 sites), plus gambling-HELP services a
     * child must always be able to reach. Subdomains are covered too.
     */
    private val KNOWN_NOT_GAMBLING = setOf(
        "casio.com", "casio.jp", "bet.com", "betzold.de", "betzold.at",
        "betterhelp.com", "alphabet.com", "begambleaware.org",
        "gamblingtherapy.org", "gamblingcommission.gov.uk",
        "gamblersanonymous.org", "ncpgambling.org",
    )

    fun isKnownNotGambling(domain: String): Boolean {
        val labels = domain.trim().lowercase().trimEnd('.').split('.')
        for (start in 0..(labels.size - 2)) {
            if (labels.subList(start, labels.size).joinToString(".") in KNOWN_NOT_GAMBLING) {
                return true
            }
        }
        return false
    }

    fun isGambling(context: Context, domain: String): Boolean {
        // Only real website names (at least "name.ending"), never bare endings.
        if (!domain.contains('.')) return false
        if (isKnownNotGambling(domain)) return false
        val prediction = load(context)?.predict(domain) ?: return false
        return prediction.meetsDeploymentBar && prediction.category == "gambling"
    }

    private fun load(context: Context): NameCategoryModel? {
        model?.let { return it }
        if (loadFailed) return null
        return try {
            val raw = context.assets.open(ASSET).bufferedReader().use { it.readText() }
            parse(JSONObject(raw)).also { model = it }
        } catch (_: Exception) {
            // Without the model, the bundled list and guardian rules still work.
            loadFailed = true
            null
        }
    }

    private fun parse(data: JSONObject): NameCategoryModel {
        val range = data.getJSONArray("ngramRange")
        val vocabulary = data.getJSONArray("vocabulary")
        val vocabIndex = HashMap<String, Int>(vocabulary.length() * 2)
        for (i in 0 until vocabulary.length()) vocabIndex[vocabulary.getString(i)] = i
        val coefficients = data.getJSONArray("coefficients")
        return NameCategoryModel(
            minN = range.getInt(0),
            maxN = range.getInt(1),
            vocabIndex = vocabIndex,
            idf = doubles(data.getJSONArray("idf")),
            classes = strings(data.getJSONArray("classes")),
            coefficients = Array(coefficients.length()) {
                doubles(coefficients.getJSONArray(it))
            },
            intercepts = doubles(data.getJSONArray("intercepts")),
            liveThreshold = data.getDouble("liveDeploymentThreshold"),
            liveClasses = strings(data.getJSONArray("liveDeploymentClasses")).toSet(),
        )
    }

    private fun doubles(array: JSONArray) = DoubleArray(array.length()) { array.getDouble(it) }

    private fun strings(array: JSONArray) = List(array.length()) { array.getString(it) }
}
