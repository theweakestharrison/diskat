// Diskat landing page: language menu (11 languages), interactive disk-map demo, screenshot tabs.
// No tracking, no third-party requests. Translations live in /assets/i18n/<code>.js and load on demand.
(function () {
  "use strict";

  var LANGS = [
    { code: "en", name: "English", html: "en" },
    { code: "vi", name: "Tiếng Việt", html: "vi" },
    { code: "zh", name: "简体中文", html: "zh-Hans" },
    { code: "ja", name: "日本語", html: "ja" },
    { code: "ko", name: "한국어", html: "ko" },
    { code: "es", name: "Español", html: "es" },
    { code: "pt", name: "Português", html: "pt" },
    { code: "de", name: "Deutsch", html: "de" },
    { code: "fr", name: "Français", html: "fr" },
    { code: "ru", name: "Русский", html: "ru" },
    { code: "id", name: "Bahasa Indonesia", html: "id" }
  ];
  // Bump together with ?v= in the HTML whenever CSS/JS/translations change (assets are cached for 7 days)
  var ASSET_VERSION = "3";
  var I18N = (window.DISKAT_I18N = window.DISKAT_I18N || {});

  // English text comes from the HTML itself; these keys are only used from script
  var EN_EXTRA = {
    "demo.gone": "↺ in Recycle Bin",
    "demo.toast": "Windows is protected. Diskat never deletes system folders.",
    "meta.title": document.title,
    "meta.desc": document.querySelector('meta[name="description"]').content
  };

  var nodes = Array.prototype.slice.call(document.querySelectorAll("[data-i18n]"));
  var english = {};
  nodes.forEach(function (n) {
    var k = n.getAttribute("data-i18n");
    if (!(k in english)) english[k] = n.innerHTML;
  });
  Object.keys(EN_EXTRA).forEach(function (k) { english[k] = EN_EXTRA[k]; });

  var current = "en";

  function t(key) {
    var d = I18N[current];
    return (d && d[key]) || english[key] || key;
  }

  function loadLang(code) {
    return new Promise(function (resolve, reject) {
      if (code === "en" || I18N[code]) return resolve();
      var s = document.createElement("script");
      s.src = "/assets/i18n/" + code + ".js?v=" + ASSET_VERSION;
      s.onload = function () { resolve(); };
      s.onerror = reject;
      document.head.appendChild(s);
    });
  }

  function apply(code) {
    current = code;
    var lang = LANGS.filter(function (l) { return l.code === code; })[0] || LANGS[0];
    document.querySelectorAll("[data-i18n]").forEach(function (n) {
      n.innerHTML = t(n.getAttribute("data-i18n"));
    });
    document.documentElement.lang = lang.html;
    document.title = t("meta.title");
    document.querySelector('meta[name="description"]').content = t("meta.desc");
    var hero = document.querySelector('#screens .shotpane img');
    if (hero) hero.src = code === "vi" ? "/assets/overview-vi.png" : "/assets/overview.png";
    document.getElementById("lang-current").textContent = code.toUpperCase();
    menu.querySelectorAll("button").forEach(function (b) {
      b.setAttribute("aria-checked", String(b.getAttribute("data-code") === code));
    });
  }

  function setLang(code, remember) {
    loadLang(code).then(function () {
      apply(code);
      if (remember) { try { localStorage.setItem("diskat-lang", code); } catch (e) { /* storage blocked */ } }
    }, function () { apply("en"); });
  }

  // ----- Language menu -----
  var sel = document.getElementById("langsel");
  var toggle = sel.querySelector("button");
  var menu = document.getElementById("lang-menu");
  LANGS.forEach(function (l) {
    var li = document.createElement("li");
    var b = document.createElement("button");
    b.type = "button";
    b.setAttribute("role", "menuitemradio");
    b.setAttribute("data-code", l.code);
    b.setAttribute("lang", l.html);
    b.innerHTML = l.name + "<span>" + l.code.toUpperCase() + "</span>";
    b.addEventListener("click", function () { close(); setLang(l.code, true); });
    li.appendChild(b);
    menu.appendChild(li);
  });
  function open() { sel.classList.add("open"); toggle.setAttribute("aria-expanded", "true"); }
  function close() { sel.classList.remove("open"); toggle.setAttribute("aria-expanded", "false"); }
  toggle.addEventListener("click", function (e) { e.stopPropagation(); sel.classList.contains("open") ? close() : open(); });
  document.addEventListener("click", function (e) { if (!sel.contains(e.target)) close(); });
  document.addEventListener("keydown", function (e) { if (e.key === "Escape") close(); });

  // Saved choice, else the browser's language if we have it, else English
  function initialLang() {
    var saved = null;
    try { saved = localStorage.getItem("diskat-lang"); } catch (e) { /* storage blocked */ }
    var codes = LANGS.map(function (l) { return l.code; });
    if (saved && codes.indexOf(saved) >= 0) return saved;
    var prefs = navigator.languages || [navigator.language || "en"];
    for (var i = 0; i < prefs.length; i++) {
      var p = String(prefs[i]).toLowerCase().split("-")[0];
      if (codes.indexOf(p) >= 0) return p;
    }
    return "en";
  }
  var first = initialLang();
  if (first !== "en") setLang(first, false); else apply("en");

  // ----- Interactive disk map demo -----
  var TOTAL = 476, USED = 452, freed = 0;
  var freedEl = document.getElementById("freed");
  var pctEl = document.getElementById("used-pct");
  var bar = document.getElementById("bar");
  var toast = document.getElementById("toast");
  var toastTimer;

  function fmt(gb) {
    if (gb <= 0) return "0 B";
    return (gb >= 100 ? gb.toFixed(0) : gb.toFixed(1)) + " GB";
  }
  function update() {
    var pct = Math.round((USED - freed) / TOTAL * 100);
    pctEl.textContent = pct + "%";
    bar.style.setProperty("--used", pct + "%");
    bar.classList.toggle("ok", pct < 80);
    freedEl.textContent = fmt(freed);
  }
  function showToast(msg) {
    toast.textContent = msg;
    toast.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toast.classList.remove("show"); }, 2800);
  }
  function remove(tile) {
    if (tile.classList.contains("gone")) return;
    if (tile.getAttribute("data-locked")) {
      tile.classList.remove("shake");
      void tile.offsetWidth; // restart the animation
      tile.classList.add("shake");
      showToast(t("demo.toast"));
      return;
    }
    tile.classList.add("gone");
    var hint = tile.querySelector(".hint");
    hint.setAttribute("data-i18n", "demo.gone");
    hint.innerHTML = t("demo.gone");
    freed += parseFloat(tile.getAttribute("data-gb"));
    update();
  }
  document.querySelectorAll("#treemap .tile").forEach(function (tile) {
    tile.addEventListener("click", function () { remove(tile); });
    tile.addEventListener("keydown", function (e) { if (e.key === "Delete") { e.preventDefault(); remove(tile); } });
  });
  document.getElementById("reset").addEventListener("click", function () {
    document.querySelectorAll("#treemap .tile.gone").forEach(function (tile) {
      tile.classList.remove("gone");
      var hint = tile.querySelector(".hint");
      hint.setAttribute("data-i18n", "demo.hint");
      hint.innerHTML = t("demo.hint");
    });
    freed = 0;
    update();
  });
  update();

  // ----- Screenshot tabs -----
  var tabs = document.querySelectorAll(".tab");
  var panes = document.querySelectorAll(".shotpane");
  tabs.forEach(function (tab) {
    tab.addEventListener("click", function () {
      var idx = Number(tab.getAttribute("data-shot"));
      tabs.forEach(function (x) { x.setAttribute("aria-selected", String(x === tab)); });
      panes.forEach(function (p, i) { p.classList.toggle("active", i === idx); });
    });
  });
})();
