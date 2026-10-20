// diskat.cc Worker: serves Diskat downloads from R2; everything else is the static site in ./website.
//
//   /download                      -> 302 to the latest version (LATEST_VERSION in wrangler.jsonc)
//   /download/v1.0.0/Diskat.exe    -> the file, streamed from R2 (resumable, cached for a year)
//
// Publishing a new version:
//   npx wrangler r2 object put diskat-downloads/releases/v<x.y.z>/Diskat.exe --file dist/Diskat.exe --remote
//   then set LATEST_VERSION in wrangler.jsonc and run: npx wrangler deploy

const VERSIONED = /^\/download\/v(\d+\.\d+\.\d+)\/Diskat\.exe$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/download" || url.pathname === "/download/") {
      return Response.redirect(new URL(`/download/v${env.LATEST_VERSION}/Diskat.exe`, url), 302);
    }
    const m = url.pathname.match(VERSIONED);
    if (m) return serveRelease(request, env, m[1]);
    if (url.pathname.startsWith("/download/")) return notFound(request, env, url);
    return env.ASSETS.fetch(request);
  },
};

async function serveRelease(request, env, version) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
  }
  const key = `releases/v${version}/Diskat.exe`;
  const object = request.method === "HEAD"
    ? await env.DOWNLOADS.head(key)
    : await env.DOWNLOADS.get(key, { range: request.headers, onlyIf: request.headers });
  if (!object) return notFound(request, env, new URL(request.url));

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("Content-Type", "application/vnd.microsoft.portable-executable");
  headers.set("Content-Disposition", 'attachment; filename="Diskat.exe"');
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

async function notFound(request, env, url) {
  const page = await env.ASSETS.fetch(new Request(new URL("/404.html", url), request));
  return new Response(page.body, { status: 404, headers: page.headers });
}
