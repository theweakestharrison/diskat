// Builds website/changelog.html and website/license.html from CHANGELOG.md and LICENSE,
// so the site shows them as real pages instead of linking to .md files on GitHub.
// Usage: node tools/build-pages.js   (run again whenever CHANGELOG.md or LICENSE changes)
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const site = path.join(root, "website");
const ASSET_VERSION = (fs.readFileSync(path.join(site, "assets", "app.js"), "utf8").match(/ASSET_VERSION = "(\d+)"/) || [, "1"])[1];

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

// Small Markdown subset: headings, lists, paragraphs, **bold**, `code`, [links](url)
function inline(s) {
  return esc(s)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (m, text, url) => {
      if (url.startsWith("../../releases")) url = "/releases";
      return `<a href="${url}">${text}</a>`;
    });
}

function markdown(md) {
  const out = [];
  let list = false, para = [];
  const flush = () => {
    if (para.length) { out.push(`<p>${inline(para.join(" "))}</p>`); para = []; }
    if (list) { out.push("</ul>"); list = false; }
  };
  for (const raw of md.split(/\r?\n/)) {
    const line = raw.trimEnd();
    let m;
    if (!line.trim()) { flush(); continue; }
    if (/^\[[^\]]+\]:\s/.test(line)) continue; // link reference definitions
    if ((m = line.match(/^(#{1,3})\s+(.*)$/))) {
      flush();
      const level = m[1].length;
      const text = m[2].replace(/^\[([^\]]+)\]/, "$1");
      const id = text.toLowerCase().replace(/[^a-z0-9.]+/g, "-").replace(/^-|-$/g, "");
      out.push(`<h${level} id="${id}">${inline(text)}</h${level}>`);
      continue;
    }
    if ((m = line.match(/^\s*-\s+(.*)$/))) {
      if (para.length) { out.push(`<p>${inline(para.join(" "))}</p>`); para = []; }
      if (!list) { out.push("<ul>"); list = true; }
      out.push(`<li>${inline(m[1])}</li>`);
      continue;
    }
    if (list && /^\s{2,}\S/.test(raw)) { out[out.length - 1] = out[out.length - 1].replace(/<\/li>$/, " " + inline(line.trim()) + "</li>"); continue; }
    para.push(line.trim());
  }
  flush();
  return out.join("\n");
}

function page(title, description, canonical, body) {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${title} · Diskat</title>
  <meta name="description" content="${description}">
  <link rel="canonical" href="https://diskat.cc${canonical}">
  <link rel="icon" href="/favicon.ico" sizes="any">
  <link rel="stylesheet" href="/assets/style.css?v=${ASSET_VERSION}">
</head>
<body>
<header class="nav">
  <div class="wrap nav-row">
    <a class="brand" href="/"><img src="/assets/logo-100.png" alt="" width="30" height="30">Diskat</a>
    <a class="btn btn-primary btn-sm nav-dl" href="/download">Download</a>
  </div>
</header>
<main class="wrap doc">
${body}
</main>
<footer class="foot">
  <div class="wrap foot-row">
    <span>© 2026 Diskat contributors · MIT License</span>
    <nav aria-label="Footer"><a href="/">Home</a><a href="/changelog">Changelog</a><a href="/license">License</a><a href="/privacy">Privacy</a><a href="/github">GitHub</a></nav>
  </div>
</footer>
<script src="/assets/app.js?v=${ASSET_VERSION}" defer></script>
</body>
</html>
`;
}

// Changelog: drop the top-level "# Changelog" heading, the page provides its own
const changelog = fs.readFileSync(path.join(root, "CHANGELOG.md"), "utf8").replace(/^# Changelog\s*/, "");
fs.writeFileSync(path.join(site, "changelog.html"), page(
  "Changelog", "Every Diskat release and what changed in it.", "/changelog",
  `<h1>Changelog</h1>\n${markdown(changelog)}`));

const license = fs.readFileSync(path.join(root, "LICENSE"), "utf8");
fs.writeFileSync(path.join(site, "license.html"), page(
  "License", "Diskat is open source under the MIT License.", "/license",
  `<h1>License</h1>\n<p>Diskat is free and open source under the MIT License. You can use it at home and at work, and you can change and share the code.</p>\n<pre class="license">${esc(license.trim())}</pre>`));

console.log("built changelog.html and license.html (asset v" + ASSET_VERSION + ")");
