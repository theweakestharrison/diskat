// diskat.cc Worker: serves Diskat downloads from R2; everything else is the static site in ./website.
//
//   /download                          -> 302 to the latest Windows version (LATEST_VERSION in wrangler.jsonc)
//   /download/v1.0.0/Diskat.exe        -> the file, streamed from R2 (resumable, cached for a year)
//   /download/mac                      -> 302 to the latest macOS version (LATEST_MAC_VERSION in wrangler.jsonc)
//   /download/v1.0.0/Diskat-1.0.0.dmg  -> the macOS disk image, served the same way
//   /api/latest                        -> {version, url, sha256, size, notes} for the Windows app's update check
//   /api/latest/mac                    -> the same for the macOS app (LATEST_MAC_* in wrangler.jsonc)
//
// The Windows and macOS apps are versioned separately. Publishing a new version:
//   npx wrangler r2 object put diskat-downloads/releases/v<x.y.z>/Diskat.exe --file dist/Diskat.exe --remote
//   npx wrangler r2 object put diskat-downloads/releases/v<x.y.z>/Diskat-<x.y.z>.dmg --file macos/dist/Diskat-<x.y.z>.dmg --remote
//   then set LATEST_VERSION, LATEST_SHA256 and LATEST_SIZE (Windows) or LATEST_MAC_VERSION, LATEST_MAC_SHA256 and
//   LATEST_MAC_SIZE (macOS) in wrangler.jsonc
//   and run: npx wrangler deploy

const EXE = /^\/download\/v(\d+\.\d+\.\d+)\/Diskat\.exe$/;
const DMG = /^\/download\/v(\d+\.\d+\.\d+)\/Diskat-\1\.dmg$/;

const WINDOWS = { name: () => "Diskat.exe", type: "application/vnd.microsoft.portable-executable" };
const MAC = { name: (v) => `Diskat-${v}.dmg`, type: "application/x-apple-diskimage" };

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "");
    if (path === "/download") return latest(request, env, url, WINDOWS, env.LATEST_VERSION);
    if (path === "/download/mac") return latest(request, env, url, MAC, env.LATEST_MAC_VERSION);
    let m;
    if ((m = url.pathname.match(EXE))) return serveRelease(request, env, m[1], WINDOWS);
    if ((m = url.pathname.match(DMG))) return serveRelease(request, env, m[1], MAC);
    if (url.pathname.startsWith("/download/")) return notFound(request, env, url);
    if (url.pathname === "/api/latest") return apiLatest(env, url);
    if (url.pathname === "/api/latest/mac") return apiLatestMac(env, url);
    return env.ASSETS.fetch(request);
  },
};

function latest(request, env, url, app, version) {
  if (!version) return notFound(request, env, url);
  return Response.redirect(new URL(`/download/v${version}/${app.name(version)}`, url), 302);
}

async function serveRelease(request, env, version, app) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
  }
  const filename = app.name(version);
  const key = `releases/v${version}/${filename}`;
  const object = request.method === "HEAD"
    ? await env.DOWNLOADS.head(key)
    : await env.DOWNLOADS.get(key, { range: request.headers, onlyIf: request.headers });
  if (!object) return notFound(request, env, new URL(request.url));

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("Content-Type", app.type);
  headers.set("Content-Disposition", `attachment; filename="${filename}"`);
  headers.set("ETag", object.httpEtag);
  headers.set("Accept-Ranges", "bytes");
  headers.set("Cache-Control", "public, max-age=31536000, immutable");
  headers.set("X-Content-Type-Options", "nosniff");

  // HEAD, or a conditional GET whose precondition failed: no body
  if (request.method === "HEAD" || !("body" in object) || !object.body) {
    headers.set("Content-Length", String(object.size));
    const status = request.method === "HEAD" ? 200 : 304;
    return new Response(null, { status, headers });
  }

  // Ranged request (resuming a download)
  if (object.range && request.headers.has("Range")) {
    const size = object.size;
    let start, end;
    if ("suffix" in object.range) { start = size - object.range.suffix; end = size - 1; }
    else { start = object.range.offset ?? 0; end = object.range.length != null ? start + object.range.length - 1 : size - 1; }
    headers.set("Content-Range", `bytes ${start}-${end}/${size}`);
    headers.set("Content-Length", String(end - start + 1));
    return new Response(object.body, { status: 206, headers });
  }

  headers.set("Content-Length", String(object.size));
  return new Response(object.body, { status: 200, headers });
}

// Used by Diskat's "Check for updates" (only when the user asks, or turns on the startup check).
// No cookies, no query parameters, nothing about the user is read or stored.
function apiLatest(env, url) {
  return json({
    version: env.LATEST_VERSION,
    url: new URL(`/download/v${env.LATEST_VERSION}/Diskat.exe`, url).toString(),
    sha256: env.LATEST_SHA256,
    size: Number(env.LATEST_SIZE),
    notes: new URL("/changelog", url).toString(),
  });
}

// Used by the macOS app's "Check for Updates". Without a published hash the app opens the download page instead.
function apiLatestMac(env, url) {
  const v = env.LATEST_MAC_VERSION;
  return json({
    version: v,
    url: new URL(`/download/v${v}/Diskat-${v}.dmg`, url).toString(),
    sha256: env.LATEST_MAC_SHA256 || null,
    size: Number(env.LATEST_MAC_SIZE) || null,
    notes: new URL("/changelog", url).toString(),
  });
}

function json(body) {
  return new Response(JSON.stringify(body), {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "public, max-age=300",
      "Access-Control-Allow-Origin": "*",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

// "/404", not "/404.html": with html_handling the .html URL is a redirect, which would leave an empty 404
async function notFound(request, env, url) {
  const page = await env.ASSETS.fetch(new Request(new URL("/404", url), request));
  return new Response(page.body, { status: 404, headers: page.headers });
}
