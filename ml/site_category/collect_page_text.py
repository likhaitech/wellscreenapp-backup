"""Collect the VISIBLE text of real web pages, to tune the page-word check
(PageTextClassifier.kt) on real data instead of guesses.

Run on the laptop from the repo root (Python 3.9+, no extra packages):

    python ml/site_category/collect_page_text.py

Groups (about 450 pages):
  gambling   100  random sample of raw/gambling_domains.txt (UT1) + the
                  Philippine list raw/gambling_domains_ph_researched.txt
  adult      100  raw/adult_domains_top_blocklists.txt + adult_domains_philippines.txt
  normal     200  random sample of the DNSFilter top-domains list
  education   ~60 fixed list of education/health pages (sex education, LGBT
                  support, HIV, puberty) AND "tricky" pages that talk ABOUT
                  gambling or porn without being it (news, Wikipedia,
                  gambling-addiction help). None of these may be blocked.

Only text is saved - no images, no HTML, no cookies. Output (JSON Lines):
    %USERPROFILE%\\Downloads\\wellscreen_page_text.jsonl

How pages are read: if Google Chrome is installed it renders each page in a
throw-away headless profile (so text added by JavaScript is included, like
on the phone); otherwise plain HTTP is used. --no-chrome forces plain HTTP.
Sites your internet provider blocks show a short block page; those are
marked and left out of the tuning.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import os
import random
import re
import shutil
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

RAW = Path(__file__).resolve().parent / "raw"
SEED = 20261120
MAX_CHARS = 20_000  # same cap as the phone (collectPageTexts)
MIN_WORDS = 30      # fewer words = blank, parked or ISP block page
UA = ("Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0 Mobile Safari/537.36")

# Education and health pages, plus pages that only TALK ABOUT gambling or
# adult topics. A page-word check must never block any of these.
EDUCATION_URLS = [
    # Sex education, puberty, reproductive health
    "https://www.plannedparenthood.org/learn/teens/puberty",
    "https://www.plannedparenthood.org/learn/birth-control",
    "https://www.plannedparenthood.org/learn/sexual-orientation",
    "https://www.scarleteen.com/",
    "https://kidshealth.org/en/teens/sexual-health/",
    "https://kidshealth.org/en/teens/puberty.html",
    "https://www.nhs.uk/conditions/contraception/",
    "https://www.nhs.uk/live-well/sexual-health/",
    "https://amaze.org/",
    "https://www.unfpa.org/comprehensive-sexuality-education",
    "https://www.who.int/news-room/fact-sheets/detail/hiv-aids",
    "https://www.who.int/news-room/questions-and-answers/item/comprehensive-sexuality-education",
    "https://www.unicef.org/philippines/",
    "https://medlineplus.gov/sexualhealthissues.html",
    "https://www.mayoclinic.org/healthy-lifestyle/sexual-health/basics/sexual-health-basics/hlv-20049432",
    "https://my.clevelandclinic.org/health/articles/puberty",
    "https://www.healthychildren.org/English/ages-stages/gradeschool/puberty/Pages/default.aspx",
    "https://www.avert.org/",
    "https://likhaan.org/",
    # LGBT support and HIV (Philippines and international)
    "https://www.thetrevorproject.org/resources/",
    "https://www.thetrevorproject.org/resources/article/understanding-sexual-orientation/",
    "https://itgetsbetter.org/",
    "https://glaad.org/",
    "https://pflag.org/",
    "https://www.hrc.org/resources",
    "https://www.stonewall.org.uk/",
    "https://www.loveyourself.ph/",
    # Wikipedia articles ABOUT gambling / adult topics (encyclopedic)
    "https://en.wikipedia.org/wiki/Online_gambling",
    "https://en.wikipedia.org/wiki/Sports_betting",
    "https://en.wikipedia.org/wiki/Casino",
    "https://en.wikipedia.org/wiki/Slot_machine",
    "https://en.wikipedia.org/wiki/Cockfighting_in_the_Philippines",
    "https://en.wikipedia.org/wiki/Philippine_Amusement_and_Gaming_Corporation",
    "https://en.wikipedia.org/wiki/Pornography",
    "https://en.wikipedia.org/wiki/Sex_education",
    "https://en.wikipedia.org/wiki/LGBT",
    "https://en.wikipedia.org/wiki/Problem_gambling",
    "https://tl.wikipedia.org/wiki/Sugal",
    # Gambling-addiction help (mentions bets, casinos, deposits)
    "https://www.begambleaware.org/",
    "https://www.gamblersanonymous.org/",
    "https://www.ncpgambling.org/help-treatment/",
    "https://www.gamcare.org.uk/",
    "https://www.gamblingtherapy.org/",
    # News and sports that mention betting, odds, e-sabong, POGOs
    "https://www.rappler.com/",
    "https://newsinfo.inquirer.net/",
    "https://www.philstar.com/",
    "https://www.gmanetwork.com/news/",
    "https://news.abs-cbn.com/",
    "https://www.bbc.com/news",
    "https://www.espn.com/nba/",
    "https://www.espn.com/boxing/",
    "https://www.pba.ph/",
    "https://www.pagcor.ph/",
    # Ordinary school and reference sites
    "https://www.deped.gov.ph/",
    "https://www.khanacademy.org/",
    "https://www.britannica.com/topic/gambling",
    "https://www.britannica.com/science/puberty",
    "https://www.coursera.org/",
    "https://www.up.edu.ph/",
    "https://www.redcross.org.ph/",
]

SKIP_TAGS = {"script", "style", "noscript", "template", "svg", "head", "iframe", "object"}


class VisibleText(HTMLParser):
    """Text a screen reader would get: element text plus alt/aria labels."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.skip = 0
        self.parts: list[str] = []
        self.chars = 0

    def _add(self, text: str) -> None:
        text = " ".join(text.split())
        if text and self.chars < MAX_CHARS:
            self.parts.append(text)
            self.chars += len(text)

    def handle_starttag(self, tag, attrs):
        if tag in SKIP_TAGS:
            self.skip += 1
            return
        if self.skip:
            return
        a = dict(attrs)
        for key in ("alt", "aria-label", "title"):
            if a.get(key):
                self._add(a[key])
        if tag == "input" and a.get("type") in {"submit", "button"} and a.get("value"):
            self._add(a["value"])

    def handle_endtag(self, tag):
        if tag in SKIP_TAGS and self.skip:
            self.skip -= 1

    def handle_data(self, data):
        if not self.skip:
            self._add(data)


def visible_texts(page_html: str) -> list[str]:
    parser = VisibleText()
    try:
        parser.feed(page_html)
        parser.close()
    except Exception:  # broken HTML: keep what was read
        pass
    return parser.parts


def read_list(*names: str) -> list[str]:
    out: list[str] = []
    for name in names:
        for line in (RAW / name).read_text(encoding="utf-8").splitlines():
            line = line.strip().lower()
            if line and not line.startswith("#"):
                out.append(line.split(",")[0])
    return list(dict.fromkeys(out))


def find_chrome() -> str | None:
    candidates = [
        shutil.which("chrome"), shutil.which("google-chrome"), shutil.which("chromium"),
        os.path.expandvars(r"%ProgramFiles%\Google\Chrome\Application\chrome.exe"),
        os.path.expandvars(r"%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"),
        os.path.expandvars(r"%LocalAppData%\Google\Chrome\Application\chrome.exe"),
    ]
    return next((c for c in candidates if c and os.path.isfile(c)), None)


_CTX = ssl.create_default_context()


def http_get(url: str, timeout: float = 10) -> tuple[str, str]:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "en,fil;q=0.8"})
    with urllib.request.urlopen(req, timeout=timeout, context=_CTX) as resp:
        if "html" not in (resp.headers.get("Content-Type") or "html"):
            raise ValueError("not a web page")
        raw = resp.read(2_000_000)
        charset = resp.headers.get_content_charset() or "utf-8"
        return resp.geturl(), raw.decode(charset, errors="replace")


def chrome_dom(chrome: str, url: str, timeout: float = 40) -> str:
    profile = tempfile.mkdtemp(prefix="ws_pages_")
    try:
        out = subprocess.run(
            [chrome, "--headless=new", "--disable-gpu", "--no-first-run",
             "--disable-extensions", "--mute-audio", "--disable-notifications",
             f"--user-data-dir={profile}", f"--user-agent={UA}",
             "--window-size=412,915", "--virtual-time-budget=8000",
             "--dump-dom", url],
            capture_output=True, timeout=timeout,
        )
        return out.stdout.decode("utf-8", errors="replace")
    finally:
        shutil.rmtree(profile, ignore_errors=True)


def fetch(group: str, target: str, chrome: str | None) -> dict:
    urls = [target] if target.startswith("http") else [f"https://{target}/", f"http://{target}/"]
    domain = re.sub(r"^https?://(www\.)?", "", urls[0]).split("/")[0]
    record = {"group": group, "domain": domain, "url": urls[0], "ok": False}
    for url in urls:
        try:
            final_url, page = http_get(url)  # also a quick "is it alive" check
            method = "http"
            if chrome:
                rendered = chrome_dom(chrome, final_url)
                if len(rendered) > 200:
                    page, method = rendered, "chrome"
            texts = visible_texts(page)
            words = sum(len(t.split()) for t in texts)
            record.update(url=url, final_url=final_url, method=method,
                          texts=texts, words=words, ok=words >= MIN_WORDS)
            if not record["ok"]:
                record["error"] = f"only {words} words (blank, parked or blocked page)"
            return record
        except Exception as exc:  # dead site, TLS error, timeout...
            record["error"] = f"{type(exc).__name__}: {exc}"[:200]
    return record


def collect(group: str, pool: list[str], want: int, chrome: str | None,
            workers: int, out, max_tries: int) -> int:
    got = tried = 0
    print(f"\n[{group}] need {want} readable pages (from {len(pool)} candidates)")
    with cf.ThreadPoolExecutor(max_workers=workers) as ex:
        pending: set = set()
        it = iter(pool)
        while got < want:
            while len(pending) < workers and tried < min(max_tries, len(pool)):
                pending.add(ex.submit(fetch, group, next(it), chrome))
                tried += 1
            if not pending:
                break
            done, pending = cf.wait(pending, return_when=cf.FIRST_COMPLETED)
            for fut in done:
                rec = fut.result()
                if rec["ok"] and got >= want:
                    continue
                out.write(json.dumps(rec, ensure_ascii=False) + "\n")
                out.flush()
                if rec["ok"]:
                    got += 1
            print(f"  {group}: {got}/{want} readable, {tried} tried", end="\r")
        for fut in pending:
            fut.cancel()
    print(f"  {group}: {got}/{want} readable, {tried} tried          ")
    return got


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=str(Path.home() / "Downloads" / "wellscreen_page_text.jsonl"))
    ap.add_argument("--no-chrome", action="store_true", help="plain HTTP only (no JavaScript)")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--scale", type=float, default=1.0, help="0.1 = quick 10%% trial run")
    ap.add_argument("--only", default="",
                    help="comma-separated sites to read instead of the groups, e.g. "
                         "--only teenfilipina.com,kifpy.com (saved as group 'check')")
    args = ap.parse_args()

    chrome = None if args.no_chrome else find_chrome()
    print("Reading pages with", f"headless Chrome ({chrome})" if chrome else "plain HTTP")

    if args.only:
        sites = [s.strip().lower() for s in args.only.split(",") if s.strip()]
        out_path = args.out
        if out_path.endswith("wellscreen_page_text.jsonl"):
            out_path = out_path.replace("wellscreen_page_text.jsonl", "wellscreen_page_check.jsonl")
        with open(out_path, "w", encoding="utf-8") as out:
            got = collect("check", sites, len(sites), chrome, args.workers, out,
                          max_tries=len(sites))
        print(f"\nReadable: {got} of {len(sites)}. Saved: {out_path}")
        print("Only page TEXT was saved. Tell Claude it is done.")
        return

    rng = random.Random(SEED)
    gambling = read_list("gambling_domains.txt")
    rng.shuffle(gambling)
    ph_gambling = read_list("gambling_domains_ph_researched.txt")
    adult = read_list("adult_domains_philippines.txt", "adult_domains_top_blocklists.txt")
    rng.shuffle(adult)
    normal = read_list("safe_domains_dnsfilter_raw.txt")[:20_000]
    rng.shuffle(normal)

    def n(x: int) -> int:
        return max(1, round(x * args.scale))

    started = time.time()
    counts = {}
    with open(args.out, "w", encoding="utf-8") as out:
        counts["gambling"] = collect("gambling", ph_gambling + gambling, n(100), chrome,
                                     args.workers, out, max_tries=2500)
        counts["adult"] = collect("adult", adult, n(100), chrome, args.workers, out, max_tries=1500)
        counts["normal"] = collect("normal", normal, n(200), chrome, args.workers, out, max_tries=2500)
        counts["education"] = collect("education", EDUCATION_URLS, len(EDUCATION_URLS), chrome,
                                      args.workers, out, max_tries=len(EDUCATION_URLS))
    mins = (time.time() - started) / 60
    print(f"\nDone in {mins:.0f} min. Readable pages: {counts}")
    print("Saved:", args.out)
    print("Only page TEXT was saved. Tell Claude it is done - it reads the file from Downloads.")


if __name__ == "__main__":
    sys.exit(main())
