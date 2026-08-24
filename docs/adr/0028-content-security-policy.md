# 0028. Content-Security-Policy for the web bundle

Date: 2026-08-24

## Status

Accepted.

## Context

`server/Caddyfile`'s site-wide `header` block sends `Cross-Origin-Opener-Policy`,
`Cross-Origin-Embedder-Policy`, `X-Content-Type-Options`, `X-Frame-Options`,
`Referrer-Policy` and HSTS (#123, #153), but no `Content-Security-Policy`. #123
deferred CSP on purpose: this is a CanvasKit Flutter build, which needs
`wasm-unsafe-eval` to compile WebAssembly, and the right directive set had to
be checked against a real build rather than assumed (#152).

Checked by running `flutter build web --release` in `app/` and reading the
output rather than guessing:

- `build/web/flutter_bootstrap.js`'s own URL-resolution function —
  `n.canvasKitBaseUrl ? n.canvasKitBaseUrl : e.engineRevision &&
  !e.useLocalCanvasKit ? gstatic-CDN-URL : "canvaskit"` — and the emitted
  `_flutter.buildConfig` sets `engineRevision` with no `useLocalCanvasKit`.
  That resolves to `https://www.gstatic.com/flutter-canvaskit/<revision>/`,
  not the local `canvaskit/` directory the same build also writes to
  `build/web/` unused. `.github/workflows/cd.yml:83` builds with plain
  `flutter build web --dart-define=...`, no `--no-web-resources-cdn`, so the
  live deployment fetches CanvasKit's JS and `.wasm` from Google's CDN on
  every cold load today, confirmed against the actual build config rather
  than assumed from the flag's default.
- `main.dart.js` calls `URL.createObjectURL` three times — genuine `blob:`
  URLs get created at runtime (file picker preview), not a hypothetical.
- `main.dart.js` references `drift_worker.js` by plain relative path — a
  same-origin `Worker`, no `blob:` needed for it.
- The build's single `builds` entry uses `renderer: "canvaskit"`, not
  `skwasm`; the `skwasm*.js`/`.ww.js` worker-spawning code in
  `build/web/canvaskit/` is present but dead in this build, so it does not
  drive the policy.
- `app/web/index.html` has one static inline `<style>` block, and
  `flutter_bootstrap.js`/the engine inject further style tags at runtime
  (loading indicator, text measurement) — no nonce is reachable from a
  static Caddy file server, so `style-src` needs `'unsafe-inline'` rather
  than a hash or nonce.
- No other external host appears in `flutter.js`, `flutter_bootstrap.js` or
  `main.dart.js` outside of doc-comment URLs (github.com, w3.org,
  flutter.dev, drift.simonbinder.eu, fonts.gstatic.com) that are string
  literals in error messages and license text, not endpoints the running
  app fetches — confirmed by reading the surrounding code, not by the string
  match alone.

## Decision

Add one `Content-Security-Policy` value to `server/Caddyfile`'s `header`
block:

```
Content-Security-Policy "default-src 'self'; script-src 'self' 'wasm-unsafe-eval' https://www.gstatic.com; worker-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self' https://www.gstatic.com; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; manifest-src 'self'"
```

`https://www.gstatic.com` is allowed in `script-src` (the dynamic `import()`
of `canvaskit.js`) and `connect-src` (the `fetch()` behind
`WebAssembly.instantiateStreaming` for `canvaskit.wasm`) because the current
build genuinely depends on it, not by default trust in a third party.
`frame-ancestors 'none'` restates `X-Frame-Options: DENY` in the modern
directive browsers actually prefer.

## Alternatives considered

**Report-only first, enforce later.** Rejected: this is a static Caddy
config with no report-collection endpoint to send `report-to` violations to,
so `Content-Security-Policy-Report-Only` would produce console warnings a
reader never reads and nobody collects. What replaces it is the manual pass
recorded under *Verification* — serve the real build under this exact header
block, walk every screen, read the DevTools console — which is the project's
existing gate for anything a reader sees. That makes the enforcement safe
only once the pass has actually been made; it is not a reason to enforce
before it.

**Bundle CanvasKit locally and drop the gstatic dependency**
(`--no-web-resources-cdn` in the build). Rejected as out of scope here: it
is a build/CD change (`.github/workflows/cd.yml`), not a Caddyfile change,
and changes what ships in every build, not just what headers wrap it. Worth
its own issue — an accessibility tool importing a third-party CDN fetch into
its critical rendering path is a real dependency, not a hypothetical one,
and removing it stops working the moment gstatic is unreachable or blocked
by the reader's own network. Tracked as #160 rather than folded in here;
that issue also carries the CSP narrowing back to `'self'` that has to land
in the same change, since dropping the CDN without narrowing the policy
leaves a permission nothing uses.

**`style-src` without `'unsafe-inline'`, using a hash.** Rejected: the
static inline `<style>` in `app/web/index.html` could be hashed, but the
engine injects further inline styles at runtime whose content is not known
ahead of the build, so a hash-only policy would still need `'unsafe-inline'`
for those and gains nothing by hashing the one block that could be hashed.

## Consequences

A wrong directive breaks the app outright rather than degrading — a missing
`script-src` origin means CanvasKit or the entrypoint script fails to load
and the reader sees `startup_failure.dart`'s screen instead of the app. This
is why the gate for this decision is serving the actual release build under
the actual header block and walking the golden paths in a browser, not
`flutter build web` succeeding.

Any future dependency on a new external host (a font CDN, an analytics
script, a different CDN for CanvasKit) needs a CSP update in the same PR, or
it fails silently in the same way a missing header does today, except loud —
a console violation and a broken feature, not silence.

## Verification

Built in the PR implementing this decision (#159, closing #152).

What was run there:

- `flutter build web --release`, with `flutter_bootstrap.js`, `flutter.js`
  and `main.dart.js` read directly to enumerate every external host, `blob:`
  URL and worker the running app actually reaches for. The directive set
  above comes from that reading.
- The build's output served through a local `caddy:2` container under this
  exact header block. `curl -sS -i` confirms the header value serializes as
  written, and every same-origin asset the policy depends on
  (`main.dart.js`, `flutter_bootstrap.js`, `flutter.js`, `drift_worker.js`,
  `sqlite3.wasm`, `manifest.json`, `favicon.png`) returns 200 under it.

What was **not** run there, and is the gate this decision actually needs:
the interactive pass — the deployed bundle open in a browser with the
DevTools console visible, walking import an EPUB, RSVP play, continuous
scroll, and sign in and sync, confirming no `Refused to …` violation
appears. No browser was driven in that session. A `curl` for a 200 proves
an asset is reachable; it does not prove the engine ran, and this policy's
failure mode is a runtime refusal, not a missing file.

Until that pass is made against the deployed site, this ADR records a
decision whose consequence has been reasoned about and not yet observed.
An earlier revision of this section claimed the browser walk as done; it
was not, and the claim is corrected here rather than quietly dropped,
because a rejected alternative above (report-only first) was rejected
partly on the strength of it.
