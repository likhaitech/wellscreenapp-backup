# Page-word check: thresholds measured on real pages

Measured 21 Nov 2026 for `PageTextClassifier.kt` (branch `rey-sitecheck`).

## Data

Collected with `collect_page_text.py` on REY's laptop (Philippines, home
internet, headless Chrome so JavaScript text is included; 12 pages fell back
to plain HTTP). Only the visible text was kept; the text file stays on the
laptop and is not in the repo.

| Group | Source | Readable pages |
|---|---|---|
| Gambling | UT1 gambling list (random) + 81 PH-researched domains | 100 (356 tried) |
| Adult | Our adult list (Block List Project + StevenBlack + DNSFilter, + PH NTC) | 100 (808 tried) |
| Normal | DNSFilter top domains (random) | 200 (563 tried) |
| Education / health / news | Fixed list of 60 pages: sex education, LGBT support, HIV, puberty, Wikipedia articles on gambling and pornography, gambling-addiction help, PH news and sports | 39 of 60 |

21 education pages could not be read (the site refused the automated reader
or timed out), e.g. Planned Parenthood and Rappler; they were not tested.

"Not a real page": 24 gambling, 7 adult and 3 normal pages turned out to be
domain-for-sale / expired / parked / "not available in your country" / error
pages. They are reported separately, because no page-word check can (or
should) block a page that shows no gambling or adult content.

## How the threshold was chosen

The same Kotlin code that ships in the app was compiled and run on every
page. Rule from the plan: pick the lowest values that block ZERO
education/health pages and almost no normal pages.

1. First version (block only with an action phrase like "deposit bonus"):
   0 education/normal pages blocked, but many obvious sites were only a hint
   because they show games or videos BEFORE login (e.g. a PH casino lobby
   with 24 points and no "deposit" button yet; adult tube pages with 17
   explicit words).
2. Added a second way to block: many different single WORDS (topic phrases
   like "online casino" and "sports betting" do not count, so a news story
   ABOUT gambling can't reach it). Tried 5-8 gambling words:
   - 5 words: blocked 2 education pages (Wikipedia gambling articles in
     English and Filipino, 5 words each) -> rejected
   - **6 words: 0 education, 0 normal blocked -> chosen (lowest safe value)**
   - 7-8 words: also safe, but blocked 5 fewer gambling sites
3. Adult: the highest non-adult page was the Wikipedia article on
   pornography (4 explicit words) -> **5 explicit words** is the lowest safe
   value.

Margins: the chosen values are only 1 above the highest education page on
each side (5 gambling words; 4 adult words). Those pages are Wikipedia,
which is also on the education allow list, so in the app it is never
checked at all.

## Results with the chosen values (STRONG_GAMBLING_WORDS = 6, STRONG_ADULT_WORDS = 5)

| Group | Blocked | Review (hint) | Nothing |
|---|---|---|---|
| Gambling, real pages (76) | 46 (61%) | 11 (14%) | 19 (25%) |
| Adult, real pages (93) | 77 (83%) | 3 (3%) | 13 (14%) |
| Normal (197) | **0** | 2 (1%) | 195 |
| Education / health / news (39) | **0** | 1 (Wikipedia, on the allow list) | 38 |
| Not real pages (34) | 0 | 0 | 34 |

Before step 2 (action phrase required): gambling 35 blocked / 22 hint,
adult 63 blocked / 14 hint, same zero blocks on normal and education.

The 2 normal hints: a bank page (welcome bonus, deposit, payout) and an
MSN casual-games page (online casino, poker, blackjack). For a child aged 7+
these only send the guardian a "Review this website" alert.

What the 19 unflagged gambling pages were: mostly non-English sites
(Vietnamese, Russian, Spanish, Portuguese, French, Finnish, Azerbaijani),
plus pages that are not really gambling pages (a casino-hotel and resort, an
art museum called "Casino Luxembourg", a lottery results site, SEO and
link-building services, cookie walls). The 13 unflagged adult pages were
mostly 18+ age gates, login/sign-up pages and chat sites that show almost
no words until the visitor clicks "Enter".

## Honest limits

- 439 pages is a small sample; results on other pages may differ.
- The word lists are English and Filipino. Sites in other languages are
  mostly missed by this check (the address lists, keywords and gambling AI
  still apply to them).
- Age gates and login walls hide the content, so the check runs again when
  the child clicks through (every 2 seconds, up to 12 times in 2 minutes).
- The education group did not include PH news ARTICLES about gambling
  (the news sites failed to load); unit tests cover a typical headline.
