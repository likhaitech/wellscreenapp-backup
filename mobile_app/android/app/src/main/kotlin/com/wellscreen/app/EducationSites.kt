package com.wellscreen.app

import java.util.Locale

/**
 * Education and health sites that WellScreen's AUTOMATIC checks never block
 * (keywords, lists, gambling AI, page words, Cloudflare). A guardian's own
 * Block rule still works on them - the guardian always has the last word.
 *
 * Why: a child researching sex education, puberty, HIV or LGBT topics for
 * school must not be blocked by a filter that mistakes a health page for an
 * adult one. Keep this list in sync with lib/services/education_sites.dart.
 */
object EducationSites {
    /** Whole domain endings: schools and government sites. */
    val SUFFIXES = listOf(
        ".edu", ".edu.ph", ".gov", ".gov.ph", ".ac.uk", ".edu.au", ".int",
    )

    /** Specific sites (and their subdomains). */
    val DOMAINS = setOf(
        // Encyclopedias and learning
        "wikipedia.org", "wikimedia.org", "wiktionary.org", "britannica.com",
        "khanacademy.org", "coursera.org", "edx.org",
        // International and Philippine health bodies
        "who.int", "unicef.org", "unfpa.org", "unaids.org", "unesco.org",
        "redcross.org", "redcross.org.ph",
        // Child and teen health
        "kidshealth.org", "nhs.uk", "mayoclinic.org", "medlineplus.gov",
        "clevelandclinic.org", "hopkinsmedicine.org", "healthychildren.org",
        // Sex education and reproductive health
        "plannedparenthood.org", "scarleteen.com", "amaze.org", "avert.org",
        "likhaan.org", "itsyoursexlife.com",
        // HIV and LGBT support
        "loveyourself.ph", "thetrevorproject.org", "itgetsbetter.org",
        "glaad.org", "pflag.org", "stonewall.org.uk", "hrc.org",
    )

    fun isProtected(domain: String): Boolean {
        val d = domain.trim().lowercase(Locale.ROOT).trimEnd('.').removePrefix("www.")
        if (d.isEmpty()) return false
        if (SUFFIXES.any { d.endsWith(it) }) return true
        val labels = d.split('.')
        for (start in 0..(labels.size - 2)) {
            if (labels.subList(start, labels.size).joinToString(".") in DOMAINS) return true
        }
        return false
    }
}
