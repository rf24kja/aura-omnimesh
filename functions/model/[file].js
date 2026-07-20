// Cloudflare Pages Function: same-origin proxy for the ONNX model.
//
// Why this exists: the web light client fetches the 76 MB model at runtime
// (Pages caps static files at 25 MB, so it cannot live in the bundle), and
// GitHub release assets do NOT send CORS headers — a cross-origin fetch()
// from the app is blocked by the browser. Serving the bytes from this same
// origin sidesteps CORS entirely and keeps the $0 / zero-accounts posture
// (no R2, no bucket, no card).
//
// The upstream is pinned to an exact release tag, NOT /latest/ — the model
// version and the app build are coupled (tokenizer + INT32 input surface),
// and /latest/ also hides pre-releases.

const RELEASE_BASE =
  'https://github.com/rf24kja/aura-omnimesh/releases/download/v1.0.0/';

// Fail-closed allowlist: this proxy serves exactly the artifacts the app
// needs, never arbitrary release files.
const ALLOWED = new Set(['minilm_multilingual_trimmed_v2.onnx']);

export async function onRequestGet(context) {
  const file = context.params.file;
  if (!ALLOWED.has(file)) {
    return new Response('not found', { status: 404 });
  }

  // Edge-cache the model so repeat loads skip the GitHub round trip. The
  // asset is immutable (versioned filename + pinned tag), so a year is
  // honest. Cache failures must never break serving — best effort only.
  const cacheKey = new Request(new URL(context.request.url).toString());
  const cache = caches.default;
  try {
    const hit = await cache.match(cacheKey);
    if (hit) return hit;
  } catch (_) {
    /* cache miss path below */
  }

  const upstream = await fetch(RELEASE_BASE + file, { redirect: 'follow' });
  if (!upstream.ok || !upstream.body) {
    return new Response('upstream unavailable', { status: 502 });
  }

  const headers = new Headers({
    'Content-Type': 'application/octet-stream',
    'Cache-Control': 'public, max-age=31536000, immutable',
    'X-Content-Type-Options': 'nosniff',
  });
  const length = upstream.headers.get('Content-Length');
  if (length) headers.set('Content-Length', length);

  const response = new Response(upstream.body, { status: 200, headers });
  try {
    context.waitUntil(cache.put(cacheKey, response.clone()));
  } catch (_) {
    /* streaming through uncached is still correct */
  }
  return response;
}
