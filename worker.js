// Cloudflare Worker: serves the app (ASSETS) plus the handover images in R2.
//
//   PUT /api/images/<sha256>.<ext>   upload (needs the team passcode)
//   GET /images/<sha256>.<ext>       download
//
// Images are content-addressed (the key is the SHA-256 of the bytes), so an
// upload can be retried or repeated safely and a URL never changes meaning.
// Job data itself lives in Supabase; the passcode is checked there too, via
// the handover_check function, so this Worker holds no secrets.

const IMAGE_KEY = /^[0-9a-f]{64}\.(png|jpg|jpeg|gif|webp|bmp|svg)$/;
const MAX_BYTES = 25 * 1024 * 1024;
const CONTENT_TYPES = {
  png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif",
  webp: "image/webp", bmp: "image/bmp", svg: "image/svg+xml",
};

// Passcodes that Supabase accepted recently, so a batch of uploads doesn't
// check the same passcode dozens of times. Per isolate, best effort.
const accepted = new Map();
const ACCEPT_MS = 5 * 60 * 1000;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname.startsWith("/api/images/")) {
      const key = url.pathname.slice("/api/images/".length);
      if (!IMAGE_KEY.test(key)) return new Response("Not found", { status: 404 });
      if (request.method !== "PUT") {
        return new Response("Method not allowed", { status: 405, headers: { Allow: "PUT" } });
      }
      return putImage(request, env, key);
    }

    if (url.pathname.startsWith("/images/")) {
      const key = url.pathname.slice("/images/".length);
      if (!IMAGE_KEY.test(key)) return new Response("Not found", { status: 404 });
      if (request.method !== "GET" && request.method !== "HEAD") {
        return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
      }
      return getImage(request, env, key);
    }

    return env.ASSETS.fetch(request);
  },
};

async function putImage(request, env, key) {
  if (!(await passcodeOk(request.headers.get("X-Handover-Passcode"), env))) {
    return new Response("Wrong passcode", { status: 401 });
  }
  const bytes = await request.arrayBuffer();
  if (bytes.byteLength === 0) return new Response("Missing body", { status: 400 });
  if (bytes.byteLength > MAX_BYTES) return new Response("Image too large", { status: 413 });

  // Refuse anything whose bytes don't match the name, so nobody can park
  // arbitrary content under a key that looks like someone else's image.
  const digest = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((b) => b.toString(16).padStart(2, "0")).join("");
  if (digest !== key.split(".")[0]) return new Response("Checksum mismatch", { status: 400 });

  const ext = key.split(".")[1];
  await env.IMAGES.put(key, bytes, { httpMetadata: { contentType: CONTENT_TYPES[ext] } });
  return Response.json({ url: "/images/" + key }, { status: 201 });
}

async function getImage(request, env, key) {
  const object = await env.IMAGES.get(key, { onlyIf: request.headers });
  if (!object) return new Response("Not found", { status: 404 });

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("ETag", object.httpEtag);
  headers.set("Cache-Control", "public, max-age=31536000, immutable");
  // Same origin as the app: stop an uploaded SVG from running script.
  headers.set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; sandbox");
  headers.set("X-Content-Type-Options", "nosniff");

  if (!("body" in object)) return new Response(null, { status: 304, headers });
  headers.set("Content-Length", String(object.size));
  return new Response(request.method === "HEAD" ? null : object.body, { headers });
}

async function passcodeOk(passcode, env) {
  if (!passcode) return false;
  const seen = accepted.get(passcode);
  if (seen && Date.now() - seen < ACCEPT_MS) return true;

  const res = await fetch(env.SUPABASE_URL + "/rest/v1/rpc/handover_check", {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_passcode: passcode }),
  });
  if (!res.ok) return false;
  accepted.set(passcode, Date.now());
  return true;
}
