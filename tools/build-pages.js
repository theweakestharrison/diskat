// Builds the static pages of the website from source files:
//   - website/changelog.html and website/license.html from CHANGELOG.md and LICENSE
//   - website/guides/<slug>.html and website/guides.html from site-src/guides/*.md
//   - structured data (JSON-LD) in website/index.html, taken from its own FAQ
//   - website/sitemap.xml
// Usage: node tools/build-pages.js   (run again whenever any of those sources change)
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const site = path.join(root, "website");
const ORIGIN = "https://diskat.cc";
const ASSET_VERSION = (fs.readFileSync(path.join(site, "assets", "app.js"), "utf8").match(/ASSET_VERSION = "(\d+)"/) || [, "1"])[1];
const VERSION = (fs.readFileSync(path.join(root, "Diskat.csproj"), "utf8").match(/<Version>([^<]+)<\/Version>/) || [, "1.0.0"])[1];
const TODAY = new Date().toISOString().slice(0, 10);

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const attr = (s) => esc(s).replace(/"/g, "&quot;");
const stripTags = (s) => s.replace(/<[^>]+>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&amp;/g, "&");

/** Heading id: ASCII letters, digits (and dots for version numbers); Vietnamese letters lose their accents. */
function slugify(text, keepDots) {
  const plain = text.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/đ/g, "d");
  return plain.replace(keepDots ? /[^a-z0-9.]+/g : /[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

// ---------------- Markdown subset ----------------
// Headings (# to ###), - lists, 1. lists, | tables |, paragraphs, **bold**, `code`, [links](url)

function inline(s) {
  const codes = [];
  // Inline code first, so * and [ inside it stay literal
  s = s.replace(/`([^`]+)`/g, (m, c) => { codes.push(c); return `\u0000${codes.length - 1}\u0000`; });
  s = esc(s)
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (m, text, url) => {
      if (url.startsWith("../../releases")) url = "/releases";
      return `<a href="${attr(url)}">${text}</a>`;
    });
  return s.replace(/\u0000(\d+)\u0000/g, (m, i) => `<code>${esc(codes[+i])}</code>`);
}

/** Split a table row on | that are not inside `code`. */
function cells(row) {
  const out = [];
  let cur = "", code = false;
  for (const ch of row.trim().replace(/^\||\|$/g, "")) {
    if (ch === "`") code = !code;
    if (ch === "|" && !code) { out.push(cur.trim()); cur = ""; } else cur += ch;
  }
  out.push(cur.trim());
  return out;
}

function markdown(md, opts = {}) {
  const out = [];
  const headings = [];
  let list = null, para = [], table = null;
  const flushPara = () => { if (para.length) { out.push(`<p>${inline(para.join(" "))}</p>`); para = []; } };
  const flushList = () => { if (list) { out.push(`</${list}>`); list = null; } };
  const flushTable = () => {
    if (!table) return;
    const [head, ...rows] = table.filter((r, i) => !(i === 1 && /^\|?\s*:?-{2,}/.test(r)));
    out.push('<div class="table-wrap"><table class="doc-table">');
    out.push("<thead><tr>" + cells(head).map((c) => `<th>${inline(c)}</th>`).join("") + "</tr></thead><tbody>");
    for (const r of rows) out.push("<tr>" + cells(r).map((c) => `<td>${inline(c)}</td>`).join("") + "</tr>");
    out.push("</tbody></table></div>");
    table = null;
  };
  const flush = () => { flushPara(); flushList(); flushTable(); };

  for (const raw of md.split(/\r?\n/)) {
    const line = raw.trimEnd();
    let m;
    if (!line.trim()) { flush(); continue; }
    if (/^\[[^\]]+\]:\s/.test(line)) continue; // link reference definitions
    if (line.trimStart().startsWith("|")) { flushPara(); flushList(); (table ??= []).push(line.trim()); continue; }
    flushTable();
    if ((m = line.match(/^(#{1,3})\s+(.*)$/))) {
      flush();
      const level = m[1].length;
      const text = m[2].replace(/^\[([^\]]+)\]/, "$1");
      const id = slugify(text, opts.keepDots);
      headings.push({ level, text, id });
      out.push(`<h${level} id="${id}">${inline(text)}</h${level}>`);
      continue;
    }
    const ul = line.match(/^\s*-\s+(.*)$/), ol = line.match(/^\s*\d+\.\s+(.*)$/);
    if (ul || ol) {
      flushPara();
      const kind = ul ? "ul" : "ol";
      if (list !== kind) { flushList(); out.push(`<${kind}>`); list = kind; }
      out.push(`<li>${inline((ul || ol)[1])}</li>`);
      continue;
    }
    if (list && /^\s{2,}\S/.test(raw)) { out[out.length - 1] = out[out.length - 1].replace(/<\/li>$/, " " + inline(line.trim()) + "</li>"); continue; }
    flushList();
    para.push(line.trim());
  }
  flush();
  return { html: out.join("\n"), headings };
}

// ---------------- Page shell ----------------

const UI = {
  en: {
    download: "Download", home: "Home", guides: "Guides", changelog: "Changelog", license: "License", privacy: "Privacy",
    updated: "Updated", more: "More guides", ctaTitle: "See what's filling up your disk",
    ctaText: "Diskat is a free, open-source disk space analyzer for Windows 10 and 11. One portable .exe, nothing to install.",
    ctaBtn: "Download Diskat", toc: "On this page",
  },
  vi: {
    download: "Tải về", home: "Trang chủ", guides: "Hướng dẫn", changelog: "Nhật ký thay đổi", license: "Giấy phép", privacy: "Quyền riêng tư",
    updated: "Cập nhật", more: "Hướng dẫn khác", ctaTitle: "Xem thứ gì đang chiếm ổ đĩa",
    ctaText: "Diskat là phần mềm phân tích dung lượng ổ đĩa miễn phí, mã nguồn mở cho Windows 10 và 11. Chỉ một file .exe, không cần cài đặt.",
    ctaBtn: "Tải Diskat", toc: "Trong bài này",
  },
};

function page({ lang = "en", title, description, canonical, body, head = "", type = "website" }) {
  const t = UI[lang] || UI.en;
  return `<!doctype html>
<html lang="${lang}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${esc(title)} · Diskat</title>
  <meta name="description" content="${attr(description)}">
  <link rel="canonical" href="${ORIGIN}${canonical}">
  <link rel="icon" href="/favicon.ico" sizes="any">
  <link rel="icon" type="image/png" href="/assets/favicon-32.png">
  <meta property="og:type" content="${type}">
  <meta property="og:url" content="${ORIGIN}${canonical}">
  <meta property="og:title" content="${attr(title)}">
  <meta property="og:description" content="${attr(description)}">
  <meta property="og:image" content="${ORIGIN}/assets/og.png">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="stylesheet" href="/assets/style.css?v=${ASSET_VERSION}">
${head}</head>
<body>
<header class="nav">
  <div class="wrap nav-row">
    <a class="brand" href="/"><img src="/assets/logo-100.png" alt="" width="30" height="30">Diskat</a>
    <a class="btn btn-primary btn-sm nav-dl" href="/download">${t.download}</a>
  </div>
</header>
<main class="wrap doc">
${body}
</main>
<footer class="foot">
  <div class="wrap foot-row">
    <span>© 2026 Diskat contributors · MIT License</span>
    <nav aria-label="Footer"><a href="/">${t.home}</a><a href="/guides">${t.guides}</a><a href="/changelog">${t.changelog}</a><a href="/license">${t.license}</a><a href="/privacy">${t.privacy}</a><a href="/github">GitHub</a></nav>
  </div>
</footer>
<script src="/assets/app.js?v=${ASSET_VERSION}" defer></script>
</body>
</html>
`;
}

/** JSON-LD block. "<" is escaped so the content can never close the script element. */
const ld = (obj) => `  <script type="application/ld+json">${JSON.stringify(obj).replace(/</g, "\\u003c")}</script>\n`;

const built = [];
const write = (rel, html) => { fs.mkdirSync(path.dirname(path.join(site, rel)), { recursive: true }); fs.writeFileSync(path.join(site, rel), html); built.push(rel); };

// ---------------- Changelog and license ----------------

// Only released versions go on the website: the "## [Unreleased]" section is work that hasn't shipped yet
const changelog = fs.readFileSync(path.join(root, "CHANGELOG.md"), "utf8")
  .replace(/^# Changelog\s*/, "")
  .replace(/^## \[Unreleased\][\s\S]*?(?=^## \[)/m, "");
write("changelog.html", page({
  title: "Changelog", description: "Every Diskat release and what changed in it.", canonical: "/changelog",
  body: `<h1>Changelog</h1>\n${markdown(changelog, { keepDots: true }).html}`,
}));

const license = fs.readFileSync(path.join(root, "LICENSE"), "utf8");
write("license.html", page({
  title: "License", description: "Diskat is open source under the MIT License.", canonical: "/license",
  body: `<h1>License</h1>\n<p>Diskat is free and open source under the MIT License. You can use it at home and at work, and you can change and share the code.</p>\n<pre class="license">${esc(license.trim())}</pre>`,
}));

// ---------------- Guides ----------------

function frontMatter(src) {
  const m = src.replace(/^\uFEFF/, "").match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/);
  if (!m) throw new Error("missing front matter");
  const meta = {};
  for (const line of m[1].split(/\r?\n/)) {
    const kv = line.match(/^([a-z]+):\s*(.*)$/);
    if (kv) meta[kv[1]] = kv[2].trim().replace(/^"(.*)"$/, "$1");
  }
  return { meta, body: m[2] };
}

const guideDir = path.join(root, "site-src", "guides");
const guides = fs.existsSync(guideDir)
  ? fs.readdirSync(guideDir).filter((f) => f.endsWith(".md")).sort().map((f) => {
      const { meta, body } = frontMatter(fs.readFileSync(path.join(guideDir, f), "utf8"));
      for (const k of ["title", "description", "slug", "lang", "updated"]) if (!meta[k]) throw new Error(`${f}: front matter needs "${k}"`);
      if (meta.slug + ".md" !== f) throw new Error(`${f}: slug "${meta.slug}" does not match the file name`);
      return { ...meta, body, file: f };
    })
  : [];

// Language alternates: the Vietnamese page names its English twin; link both ways
const alt = {};
for (const g of guides) if (g.alternate) { alt[g.slug] = { [g.lang]: g.slug, en: g.alternate }; alt[g.alternate] = alt[g.slug]; }
const known = new Set(guides.map((g) => g.slug));
for (const [slug, a] of Object.entries(alt)) for (const s of Object.values(a)) if (!known.has(s)) throw new Error(`alternate of ${slug} points to unknown guide ${s}`);

/** FAQ section ("## FAQ" / "## Câu hỏi thường gặp"): every ### question with the paragraphs after it. */
function faqOf(md) {
  const lines = md.split(/\r?\n/);
  const start = lines.findIndex((l) => /^##\s+(FAQ|Câu hỏi thường gặp)\s*$/i.test(l));
  if (start < 0) return [];
  const items = [];
  for (const l of lines.slice(start + 1)) {
    if (/^##\s/.test(l)) break;
    const q = l.match(/^###\s+(.*)$/);
    if (q) items.push({ q: q[1].trim(), a: [] });
    else if (items.length && l.trim()) items[items.length - 1].a.push(l.trim());
  }
  return items.map((i) => ({ q: stripTags(inline(i.q)), a: stripTags(inline(i.a.join(" "))) })).filter((i) => i.a);
}

for (const g of guides) {
  const t = UI[g.lang] || UI.en;
  const url = `/guides/${g.slug}`;
  const { html } = markdown(g.body);
  const faq = faqOf(g.body);
  const others = guides.filter((o) => o.lang === g.lang && o.slug !== g.slug);

  let head = "";
  if (alt[g.slug]) {
    for (const [lang, slug] of Object.entries(alt[g.slug])) head += `  <link rel="alternate" hreflang="${lang}" href="${ORIGIN}/guides/${slug}">\n`;
    head += `  <link rel="alternate" hreflang="x-default" href="${ORIGIN}/guides/${alt[g.slug].en}">\n`;
  }
  head += ld({
    "@context": "https://schema.org", "@type": "Article",
    headline: g.title, description: g.description, inLanguage: g.lang,
    datePublished: g.updated, dateModified: g.updated,
    mainEntityOfPage: ORIGIN + url, image: ORIGIN + "/assets/og.png",
    author: { "@type": "Organization", name: "Diskat", url: ORIGIN },
    publisher: { "@type": "Organization", name: "Diskat", logo: { "@type": "ImageObject", url: ORIGIN + "/assets/logo-256.png" } },
  });
  head += ld({
    "@context": "https://schema.org", "@type": "BreadcrumbList",
    itemListElement: [
      { "@type": "ListItem", position: 1, name: "Diskat", item: ORIGIN + "/" },
      { "@type": "ListItem", position: 2, name: t.guides, item: ORIGIN + "/guides" },
      { "@type": "ListItem", position: 3, name: g.title, item: ORIGIN + url },
    ],
  });
  if (faq.length) head += ld({
    "@context": "https://schema.org", "@type": "FAQPage",
    mainEntity: faq.map((f) => ({ "@type": "Question", name: f.q, acceptedAnswer: { "@type": "Answer", text: f.a } })),
  });

  const body = `<nav class="crumbs" aria-label="Breadcrumb"><a href="/">Diskat</a><span>/</span><a href="/guides">${t.guides}</a></nav>
<article class="guide">
<h1>${inline(g.title)}</h1>
<p class="guide-meta">${t.updated} <time datetime="${g.updated}">${g.updated}</time></p>
${html}
</article>
<aside class="guide-cta">
  <div><h2>${t.ctaTitle}</h2><p>${t.ctaText}</p></div>
  <a class="btn btn-primary" href="/download">${t.ctaBtn}</a>
</aside>
${others.length ? `<div class="guide-more"><h2>${t.more}</h2><ul>${others.map((o) => `<li><a href="/guides/${o.slug}">${esc(o.title)}</a></li>`).join("")}</ul></div>` : ""}`;

  write(`guides/${g.slug}.html`, page({ lang: g.lang, title: g.title, description: g.description, canonical: url, body, head, type: "article" }));
}

if (guides.length) {
  const card = (g) => `<li><a href="/guides/${g.slug}"><b>${esc(g.title)}</b><span>${esc(g.description)}</span></a></li>`;
  const en = guides.filter((g) => g.lang === "en"), vi = guides.filter((g) => g.lang === "vi");
  const body = `<h1>Guides</h1>
<p class="lead">Practical, step-by-step guides to finding and freeing disk space on Windows 10 and 11.</p>
<ul class="guide-list">${en.map(card).join("")}</ul>
${vi.length ? `<div class="guide-group" lang="vi"><h2>Hướng dẫn tiếng Việt</h2><ul class="guide-list">${vi.map(card).join("")}</ul></div>` : ""}`;
  write("guides.html", page({
    title: "Guides", canonical: "/guides", body,
    description: "Step-by-step guides to free up disk space on Windows: find large files, clean a full C drive, delete files that are in use, and more.",
  }));
}

// ---------------- Homepage structured data ----------------

const indexFile = path.join(site, "index.html");
let index = fs.readFileSync(indexFile, "utf8");
const homeFaq = [...index.matchAll(/<details><summary[^>]*>([\s\S]*?)<\/summary><p[^>]*>([\s\S]*?)<\/p><\/details>/g)]
  .map((m) => ({ q: stripTags(m[1]).trim(), a: stripTags(m[2]).replace(/\s+/g, " ").trim() }));
const homeLd = ld({
  "@context": "https://schema.org", "@type": "SoftwareApplication",
  name: "Diskat", url: ORIGIN + "/", downloadUrl: ORIGIN + "/download", softwareVersion: VERSION,
  operatingSystem: "Windows 10, Windows 11", applicationCategory: "UtilitiesApplication",
  description: (index.match(/<meta name="description" content="([^"]+)"/) || [, ""])[1],
  image: ORIGIN + "/assets/logo-256.png", license: ORIGIN + "/license", isAccessibleForFree: true,
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
}) + ld({
  "@context": "https://schema.org", "@type": "FAQPage",
  mainEntity: homeFaq.map((f) => ({ "@type": "Question", name: f.q, acceptedAnswer: { "@type": "Answer", text: f.a } })),
});
const block = `  <!-- ld:start (generated by tools/build-pages.js) -->\n${homeLd}  <!-- ld:end -->\n`;
// \r?\n: Windows checkouts have CRLF. The first block is replaced and any extra copy is dropped.
const LD = /  <!-- ld:start[\s\S]*?<!-- ld:end -->\r?\n/g;
let firstLd = true;
index = LD.test(index)
  ? index.replace(LD, () => (firstLd ? ((firstLd = false), block) : ""))
  : index.replace("</head>", block + "</head>");
fs.writeFileSync(indexFile, index);
built.push("index.html (JSON-LD, " + homeFaq.length + " FAQ)");

// ---------------- Sitemap ----------------
// Plain sitemap, no xhtml:link alternates: the language versions of each guide are already
// declared with <link rel="alternate" hreflang> in its <head> (see above), which search engines
// treat the same. Any XHTML element in the file makes browsers render it as a page of run-on
// text instead of showing the XML tree.

const urls = [
  { loc: "/", lastmod: TODAY, priority: "1.0" },
  ...(guides.length ? [{ loc: "/guides", lastmod: TODAY, priority: "0.8" }] : []),
  ...guides.map((g) => ({ loc: `/guides/${g.slug}`, lastmod: g.updated, priority: "0.7" })),
  { loc: "/changelog", lastmod: TODAY, priority: "0.5" },
  { loc: "/license", lastmod: TODAY, priority: "0.3" },
  { loc: "/privacy", lastmod: TODAY, priority: "0.3" },
];
const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map((u) => `  <url><loc>${ORIGIN}${u.loc}</loc><lastmod>${u.lastmod}</lastmod><priority>${u.priority}</priority></url>`).join("\n")}
</urlset>
`;
fs.writeFileSync(path.join(site, "sitemap.xml"), xml);
built.push("sitemap.xml (" + urls.length + " URLs)");

console.log("built (asset v" + ASSET_VERSION + ", app v" + VERSION + "):\n  " + built.join("\n  "));
