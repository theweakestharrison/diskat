// Checks translations against English: same keys, same {placeholders} and HTML tags, no long dashes.
// Usage: node tools/check-i18n.js <code> [<code> ...]     e.g. node tools/check-i18n.js vi ja
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");

function loadWeb(code) {
  const file = path.join(root, "website", "assets", "i18n", code + ".js");
  if (!fs.existsSync(file)) return null;
  const sandbox = { window: {} };
  new Function("window", fs.readFileSync(file, "utf8"))(sandbox.window);
  return sandbox.window.DISKAT_I18N[code];
}

function loadApp(code) {
  const name = code[0].toUpperCase() + code.slice(1);
  const file = path.join(root, "Core", "Lang", "Strings." + code + ".cs");
  if (!fs.existsSync(file)) return null;
  const src = fs.readFileSync(file, "utf8");
  if (!new RegExp("Dictionary<string, string> " + name + " = new\\(\\)").test(src)) throw new Error(file + ": field '" + name + "' not found");
  const out = {};
  const re = /\["([^"]+)"\]\s*=\s*"((?:[^"\\]|\\.)*)"/g;
  let m;
  while ((m = re.exec(src))) out[m[1]] = JSON.parse('"' + m[2] + '"');
  return out;
}

const tokens = (s) => ((s.match(/\{[^}]*\}|<\/?\w+>/g) || []).sort().join(" "));
let failures = 0;

function compare(label, en, tr) {
  if (!tr) { console.log(`MISSING  ${label}`); failures++; return; }
  const problems = [];
  for (const k of Object.keys(en)) {
    if (!(k in tr)) { problems.push(`missing key ${k}`); continue; }
    if (tokens(en[k]) !== tokens(tr[k])) problems.push(`${k}: placeholders/tags differ ("${tokens(en[k])}" vs "${tokens(tr[k])}")`);
    if (/[—–]/.test(tr[k])) problems.push(`${k}: contains a long dash`);
    if (!tr[k].trim()) problems.push(`${k}: empty`);
  }
  for (const k of Object.keys(tr)) if (!(k in en)) problems.push(`extra key ${k}`);
  if (problems.length) { failures += problems.length; console.log(`FAIL     ${label}\n  - ` + problems.join("\n  - ")); }
  else console.log(`OK       ${label} (${Object.keys(tr).length} keys)`);
}

const enWeb = loadWeb("en"), enApp = loadApp("en");
for (const code of process.argv.slice(2)) {
  compare(`website ${code}`, enWeb, loadWeb(code));
  compare(`app     ${code}`, enApp, loadApp(code));
}
process.exit(failures ? 1 : 0);
