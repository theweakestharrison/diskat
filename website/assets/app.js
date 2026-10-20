// Diskat landing page: language menu (11 languages, English by default) and the Windows/macOS download buttons.
// No tracking, no third-party requests. Translations live in /assets/i18n/<code>.js and load on demand.
(function () {
  "use strict";

  // Bump together with ?v= in the HTML whenever CSS/JS/translations change (assets are cached for 7 days)
  var ASSET_VERSION = "6";

  // Mac visitors get the macOS download as the main button and in the nav (iPads also report "Mac" but have touch).
  // Without script every page still works: Windows is the default.
  var platform = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || "";
  if (/mac/i.test(platform) && !(navigator.maxTouchPoints > 1)) {
    document.querySelectorAll("a.nav-dl").forEach(function (a) { a.href = "/download/mac"; });
    document.querySelectorAll(".cta").forEach(function (cta) {
      var win = cta.querySelector('[data-os="windows"]'), mac = cta.querySelector('[data-os="mac"]');
      if (!win || !mac) return;
      var cls = win.className; win.className = mac.className; mac.className = cls;
      var spot = document.createComment("");
      win.replaceWith(spot); mac.replaceWith(win); spot.replaceWith(mac);
    });
  }

  // The language menu is only on the home page; the other pages are English only
  if (!document.getElementById("langsel")) return;

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
  var I18N = (window.DISKAT_I18N = window.DISKAT_I18N || {});

  // English text comes from the HTML itself; the meta tags are the only strings set from script
  var english = {
    "meta.title2": document.title,
    "meta.desc3": document.querySelector('meta[name="description"]').content
  };
  document.querySelectorAll("[data-i18n]").forEach(function (n) {
    var k = n.getAttribute("data-i18n");
    if (!(k in english)) english[k] = n.innerHTML;
  });

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

  var sel = document.getElementById("langsel");
  var toggle = sel.querySelector("button");
  var menu = document.getElementById("lang-menu");

  function apply(code) {
    current = code;
    var lang = LANGS.filter(function (l) { return l.code === code; })[0] || LANGS[0];
    document.querySelectorAll("[data-i18n]").forEach(function (n) {
      n.innerHTML = t(n.getAttribute("data-i18n"));
    });
    document.documentElement.lang = lang.html;
    document.title = t("meta.title2");
    document.querySelector('meta[name="description"]').content = t("meta.desc3");
    // The app has a Vietnamese screenshot; every other language shows the English one
    var hero = document.getElementById("hero-shot");
    if (hero) hero.src = code === "vi" ? "/assets/overview-vi.png" : "/assets/overview.png";
    // Numbers in the language's own format (1,952,417 / 1.952.417 / 1 952 417)
    document.querySelectorAll("[data-num]").forEach(function (b) {
      try { b.textContent = new Intl.NumberFormat(lang.html).format(Number(b.getAttribute("data-num"))); } catch (e) { /* keep as is */ }
    });
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

  // ?lang=xx in the URL (shareable links), else the saved choice, else English (the default)
  function initialLang() {
    var codes = LANGS.map(function (l) { return l.code; });
    var fromUrl = new URLSearchParams(location.search).get("lang");
    if (fromUrl && codes.indexOf(fromUrl) >= 0) return fromUrl;
    var saved = null;
    try { saved = localStorage.getItem("diskat-lang"); } catch (e) { /* storage blocked */ }
    return saved && codes.indexOf(saved) >= 0 ? saved : "en";
  }
  var first = initialLang();
  if (first !== "en") setLang(first, false); else apply("en");
})();
