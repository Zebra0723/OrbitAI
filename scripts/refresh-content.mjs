// Fetches RSS feeds for each Vortex section, normalizes to the content.json shape.
// Sections without working feeds keep their seed entries from the existing JSON.
// Run: node scripts/refresh-content.mjs

import Parser from "rss-parser";
import { readFileSync, writeFileSync } from "fs";
import { createHash } from "crypto";

const FEEDS = {
  tennis: [
    "https://www.reddit.com/r/tennis/.rss",
    "https://www.tennis.com/rss/all",
  ],
  rabbit: [
    "https://aeon.co/feed.rss",
    "https://www.quantamagazine.org/feed/",
    "https://www.atlasobscura.com/feeds/latest",
  ],
  books: [
    "https://lithub.com/feed/",
    "https://www.themarginalian.org/feed/",
    "https://feeds.npr.org/1032/rss.xml",
  ],
  author: [
    "https://janefriedman.com/feed/",
    "https://lithub.com/feed/",
  ],
  // Prestige Mode: no reliable RSS for kid writing contests; keep seed.
  prestige: [],
  engineer: [
    "https://hackaday.com/feed/",
    "https://makezine.com/feed/",
    "https://blog.adafruit.com/feed/",
  ],
  radar: [
    "https://www.theverge.com/rss/index.xml",
    "https://www.wired.com/feed/rss",
  ],
};

const PER_FEED_LIMIT = 5;
const PER_SECTION_LIMIT = 14;
const BODY_MAX = 320;

const parser = new Parser({
  timeout: 12000,
  headers: { "User-Agent": "VortexBot/1.0 (+https://github.com/Zebra0723/vortex)" },
});

function stripHtml(s) {
  if (!s) return "";
  return s
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, " ")
    .trim();
}

function trimBody(s) {
  const t = stripHtml(s);
  if (t.length <= BODY_MAX) return t;
  const cut = t.slice(0, BODY_MAX);
  const lastSpace = cut.lastIndexOf(" ");
  return (lastSpace > 200 ? cut.slice(0, lastSpace) : cut).trim() + "…";
}

function hashId(prefix, s) {
  return prefix + "-" + createHash("sha1").update(s).digest("hex").slice(0, 10);
}

function shortSource(feedTitle, url) {
  const t = (feedTitle || "").trim();
  if (t) return t.length > 22 ? t.slice(0, 22) + "…" : t;
  try { return new URL(url).hostname.replace(/^www\./, ""); }
  catch { return "Feed"; }
}

async function fetchFeed(url) {
  try {
    const feed = await parser.parseURL(url);
    return feed;
  } catch (err) {
    console.error(`  ⚠ ${url} → ${err.message}`);
    return null;
  }
}

async function fetchSection(name, urls) {
  const items = [];
  for (const url of urls) {
    console.log(`  → ${url}`);
    const feed = await fetchFeed(url);
    if (!feed) continue;
    const sourceTag = shortSource(feed.title, url);
    const entries = (feed.items || []).slice(0, PER_FEED_LIMIT);
    for (const it of entries) {
      const title = stripHtml(it.title || "").trim();
      if (!title) continue;
      const body = trimBody(it.contentSnippet || it.content || it.summary || it["content:encoded"] || "");
      if (!body) continue;
      items.push({
        id: hashId(name, it.link || it.guid || title),
        tag: sourceTag,
        title,
        body,
        link: it.link || null,
        published: it.isoDate || it.pubDate || null,
      });
    }
  }
  // Dedupe by id
  const seen = new Set();
  const unique = items.filter((x) => (seen.has(x.id) ? false : (seen.add(x.id), true)));
  // Sort newest first; items without a date land last
  unique.sort((a, b) => {
    const da = a.published ? Date.parse(a.published) : 0;
    const db = b.published ? Date.parse(b.published) : 0;
    return db - da;
  });
  return unique.slice(0, PER_SECTION_LIMIT);
}

async function main() {
  const existing = JSON.parse(readFileSync("data/content.json", "utf8"));
  const result = { ...existing };

  for (const [name, urls] of Object.entries(FEEDS)) {
    if (urls.length === 0) {
      console.log(`${name}: no feeds configured, keeping seed (${(existing[name] || []).length} items)`);
      continue;
    }
    console.log(`${name}:`);
    const fetched = await fetchSection(name, urls);
    if (fetched.length > 0) {
      result[name] = fetched;
      console.log(`  ✓ ${fetched.length} items`);
    } else {
      console.log(`  ⚠ no items fetched, keeping seed`);
    }
  }

  result._lastUpdated = new Date().toISOString();
  writeFileSync("data/content.json", JSON.stringify(result, null, 2) + "\n");
  console.log(`\nWrote data/content.json @ ${result._lastUpdated}`);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
