"""Generate AI explainers for NASA/ESA news and NASA's Astronomy Picture of the Day.

News articles come from the Spaceflight News API and are written to
$OUTPUT_DIR/articles/<id>.json plus an index. Today's APOD is written to
$OUTPUT_DIR/articles/apod/<YYYY-MM-DD>.json. Anything already generated is skipped.
Needs ANTHROPIC_API_KEY in the environment.
"""

import datetime
import email.utils
import html
import json
import os
import pathlib
import re
import sys
import urllib.parse
import xml.etree.ElementTree as ET

import anthropic
import requests
import trafilatura

NEWS_API = "https://api.spaceflightnewsapi.net/v4/articles/"
NEWS_SITES = "NASA,ESA"
APOD_FEED = "https://science.nasa.gov/feed/apod-basic/"
APOD_NS = {"apod": "https://science.nasa.gov/apod/"}
MODEL = os.environ.get("ARTICLE_MODEL", "claude-sonnet-5-5")
MAX_PER_RUN = int(os.environ.get("MAX_PER_RUN", "10"))
OUTPUT_DIR = pathlib.Path(os.environ.get("OUTPUT_DIR", "site")) / "articles"
USER_AGENT = "laniakea-article-generator (+https://github.com/harshsepi0l/laniakea)"
MIN_SOURCE_CHARS = 400
MAX_SOURCE_CHARS = 30_000
MAX_SECTIONS = 4

SYSTEM_PROMPT = """You turn official NASA and ESA news posts, and NASA's Astronomy Picture of the Day descriptions, into clear, engaging explainers for a space-exploration app.

Rules:
- Use only facts stated in the source text. Never add numbers, names, dates, quotes, or claims that are not in it.
- Write in your own words for a curious general reader. Explain jargon briefly when it first appears.
- Organize the piece into 3 or 4 sections that follow the most important topics of the source (2 sections if the source is short). Each heading is short (2 to 6 words).
- Each section body is exactly one paragraph of 2 to 4 sentences in plain text. No line breaks, markdown, bullet points, or emoji.
- Leave out minor details rather than going over 4 paragraphs in total.
- The title is a plain, accurate headline, not clickbait.
- The summary is one or two sentences saying what happened and why it matters."""

ARTICLE_SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "summary": {"type": "string"},
        "sections": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "heading": {"type": "string"},
                    "body": {"type": "string"},
                },
                "required": ["heading", "body"],
                "additionalProperties": False,
            },
        },
    },
    "required": ["title", "summary", "sections"],
    "additionalProperties": False,
}


def fetch_latest_articles():
    response = requests.get(
        NEWS_API,
        params={"news_site": NEWS_SITES, "limit": 20, "ordering": "-published_at"},
        timeout=30,
    )
    response.raise_for_status()
    return response.json()["results"]


def extract_source_text(url):
    response = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=30)
    response.raise_for_status()
    text = trafilatura.extract(response.text, include_comments=False, include_tables=False) or ""
    return text[:MAX_SOURCE_CHARS]


def html_to_text(markup):
    text = re.sub(r"<br\s*/?>", "\n", markup, flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    return re.sub(r"[ \t]+", " ", html.unescape(text)).strip()


def fetch_todays_apod():
    response = requests.get(APOD_FEED, headers={"User-Agent": USER_AGENT}, timeout=30)
    response.raise_for_status()
    item = ET.fromstring(response.content).find("channel/item")
    published = email.utils.parsedate_to_datetime(item.findtext("pubDate")).astimezone(datetime.timezone.utc)
    explanation = html_to_text(item.findtext("apod:explanation", "", APOD_NS))
    explanation = explanation.removeprefix("Explanation:").split("Tomorrow's picture:")[0].strip()
    image = urllib.parse.urlsplit(item.findtext("apod:hdurl", "", APOD_NS).strip())
    return {
        "date": published.date().isoformat(),
        "title": html.unescape(item.findtext("title", "")).strip(),
        "url": item.findtext("apod:url", "", APOD_NS).strip(),
        "image_url": urllib.parse.urlunsplit(image._replace(query="w=1200&fit=clip")),
        "credit": html_to_text(item.findtext("apod:credit", "", APOD_NS)),
        "published_at": published.isoformat(timespec="seconds").replace("+00:00", "Z"),
        "explanation": explanation,
    }


def write_explainer(client, publisher, original_title, published_at, source_text):
    message = client.messages.create(
        model=MODEL,
        max_tokens=4000,
        system=SYSTEM_PROMPT,
        output_config={"format": {"type": "json_schema", "schema": ARTICLE_SCHEMA}},
        messages=[{
            "role": "user",
            "content": (
                f"Publisher: {publisher}\n"
                f"Original title: {original_title}\n"
                f"Published: {published_at}\n\n"
                f"<source_text>\n{source_text}\n</source_text>"
            ),
        }],
    )
    result = json.loads(next(block.text for block in message.content if block.type == "text"))
    sections = [
        {"heading": s["heading"].strip(), "body": s["body"].strip()}
        for s in result["sections"]
        if s.get("heading", "").strip() and s.get("body", "").strip()
    ]
    sections = sections[:MAX_SECTIONS]
    if not result["title"].strip() or not sections:
        raise ValueError("model returned an empty article")
    return result["title"].strip(), result["summary"].strip(), sections


def write_json(path, data):
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def rebuild_index():
    entries = []
    for path in OUTPUT_DIR.glob("*.json"):
        if not path.stem.isdigit():
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        entries.append({
            "id": data["id"],
            "title": data["title"],
            "source_name": data["source"]["name"],
            "published_at": data["published_at"],
        })
    entries.sort(key=lambda e: e["published_at"], reverse=True)
    write_json(OUTPUT_DIR / "index.json", entries)


def news_jobs():
    done = {int(p.stem) for p in OUTPUT_DIR.glob("*.json") if p.stem.isdigit()}
    pending = [a for a in fetch_latest_articles() if a["id"] not in done][:MAX_PER_RUN]
    print(f"news: {len(done)} already generated, {len(pending)} to generate")
    return [{
        "id": a["id"],
        "path": OUTPUT_DIR / f"{a['id']}.json",
        "publisher": a["news_site"],
        "original_title": a["title"],
        "url": a["url"],
        "image_url": a.get("image_url"),
        "published_at": a["published_at"],
        "source_text": lambda url=a["url"]: extract_source_text(url),
    } for a in pending]


def apod_jobs():
    apod = fetch_todays_apod()
    path = OUTPUT_DIR / "apod" / f"{apod['date']}.json"
    if path.exists():
        print(f"apod: {apod['date']} already generated")
        return []
    print(f"apod: generating {apod['date']}")
    return [{
        "id": apod["date"],
        "path": path,
        "publisher": "NASA APOD",
        "original_title": apod["title"],
        "url": apod["url"],
        "image_url": apod["image_url"],
        "published_at": apod["published_at"],
        "source_text": lambda: f"{apod['explanation']}\n\nImage credit: {apod['credit']}",
    }]


def main():
    (OUTPUT_DIR / "apod").mkdir(parents=True, exist_ok=True)
    jobs = apod_jobs() + news_jobs()

    client = anthropic.Anthropic()
    succeeded = failed = 0
    for job in jobs:
        try:
            source_text = job["source_text"]()
            if len(source_text) < MIN_SOURCE_CHARS:
                print(f"skip {job['id']}: only {len(source_text)} chars of source text")
                continue
            title, summary, sections = write_explainer(
                client, job["publisher"], job["original_title"], job["published_at"], source_text
            )
            write_json(job["path"], {
                "id": job["id"],
                "title": title,
                "summary": summary,
                "sections": sections,
                "source": {
                    "name": job["publisher"],
                    "url": job["url"],
                    "original_title": job["original_title"],
                },
                "image_url": job["image_url"],
                "published_at": job["published_at"],
                "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
                "model": MODEL,
            })
            succeeded += 1
            print(f"ok   {job['id']}: {title}")
        except (anthropic.AuthenticationError, anthropic.PermissionDeniedError) as error:
            failed += 1
            print(f"stop: API key rejected: {error}", file=sys.stderr)
            break
        except anthropic.BadRequestError as error:
            failed += 1
            print(f"fail {job['id']}: {error}", file=sys.stderr)
            if not succeeded:
                print("stop: the first request failed, so the rest would too", file=sys.stderr)
                break
        except Exception as error:
            failed += 1
            print(f"fail {job['id']}: {error}", file=sys.stderr)

    rebuild_index()
    print(f"done: {succeeded} generated, {failed} failed")
    if failed and not succeeded:
        sys.exit(1)


if __name__ == "__main__":
    main()
