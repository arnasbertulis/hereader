# 0039. Front the origin with Cloudflare, verified by Authenticated Origin Pulls

Date: 2026-09-15

## Status

Accepted.

## Context

ADR 0006 put the deployed hostname on `sslip.io` because no domain was
owned; the app's own domain (`hereader.arnasbertulis.com`, a subdomain of a
personal domain otherwise reserved for a separate portfolio site) has since
been bought and DNS repointed there. Proxying that record through Cloudflare
was considered at the same time, for its free DDoS mitigation and WAF in
front of a single 4GB VPS.

Cloudflare's proxy is not, by itself, a meaningful security boundary here.
The origin's IP address is public — it was the literal hostname under
`sslip.io` and is recorded in this repo's own git history (ADR 0006) — so
anyone can bypass Cloudflare entirely by sending requests straight to the
VPS with the right `Host` header, skipping whatever Cloudflare filters.

Proxying also changes what
[`RateLimitFilter`](../../server/src/main/java/lt/hereader/server/config/RateLimitFilter.java)
sees. It keys off `request.getRemoteAddr()`, resolved from `X-Forwarded-For`
via `server.forward-headers-strategy=framework`
(`server/src/main/resources/application.properties`). Caddy fills that
header from the peer it is talking to and ignores any client-sent copy,
which was correct while visitors connected directly. Behind Cloudflare the
peer is always a Cloudflare edge node, so every visitor routed through the
same edge would share one rate-limit bucket (ADR 0026): one abusive client
could lock out everyone else on that edge. The visitor's own address
arrives in `CF-Connecting-IP` instead — but a header that only Cloudflare
should set is only as trustworthy as the guarantee that Cloudflare sent the
request.

## Decision

Cloudflare's proxy is verified at the origin with [Authenticated Origin
Pulls](https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/):
Cloudflare presents a client TLS certificate, signed by Cloudflare's own
Origin Pull CA, on every proxied request. `server/Caddyfile` requires and
verifies that certificate (`tls { client_auth { mode require_and_verify } }`)
against `server/cloudflare-origin-pull-ca.pem` — the shared, public CA
certificate Cloudflare publishes for every account, mounted read-only into
the `caddy` container by `server/compose.yaml`. A request that doesn't carry
a valid Cloudflare client certificate is rejected at the TLS handshake,
before it reaches any application code.

With that guarantee in place, `CF-Connecting-IP` becomes a trustworthy
signal: Cloudflare sets it from its own edge connection in place of any
client-supplied copy, and now only Cloudflare can complete a TLS handshake
with this origin at all. `reverse_proxy` in the `/api/*` block overwrites
`X-Forwarded-For` with `CF-Connecting-IP` before proxying to the app, so the
rate limiter keys on the visitor again rather than on the Cloudflare edge.
Configuring `client_auth` also turns on Caddy's `strict_sni_host`, so a
client can't complete the handshake under another name and then request
this site in its `Host` header.

The global (account-wide) variant of Authenticated Origin Pulls is used
rather than the zone- or hostname-level variant that lets an account upload
its own certificate — the global certificate is shared across all Cloudflare
accounts, so it proves "this came through some Cloudflare zone," not
specifically this one. That's sufficient here: the goal is closing the
direct-to-origin bypass, not distinguishing this Cloudflare zone from
another. A stricter per-zone certificate is available later without
changing this decision if that distinction ever matters.

## Consequences

Three Cloudflare dashboard settings must be in place, and neither this repo
nor CI can set them: the DNS record proxied; SSL/TLS encryption mode
**Full (strict)** (Authenticated Origin Pulls needs Full or higher, and
strict also verifies the origin's Let's Encrypt certificate); and the
Global toggle under SSL/TLS → Origin Server → Authenticated Origin Pulls.
The toggle has to be on before a release carrying this Caddyfile deploys —
from then on Caddy rejects every handshake without the certificate,
Cloudflare's own included.

**Always Use HTTPS** stays off in Cloudflare. Caddy obtains its Let's
Encrypt certificate through the HTTP-01 challenge on port 80 — TLS-ALPN-01
can't pass through Cloudflare's TLS termination — and an edge redirect to
HTTPS would send the first challenge to a port 443 that has no certificate
for this name yet. Caddy already redirects HTTP to HTTPS itself, so the
Cloudflare toggle would add nothing.

Local testing already stopped short of the Caddy layer entirely (ADR 0006's
"Local testing intentionally stops short of the Caddy layer") because the
hostname resolves to the real server, not a developer's machine. This
adds a second reason a local Caddy could never pass anyway: it has no
Cloudflare in front of it to present a client certificate. No change to the
existing local-dev path (`docker compose up db app` against the service
directly), and no new gap beyond the one already accepted.

The CA certificate is committed to the repo in plaintext
(`server/cloudflare-origin-pull-ca.pem`). This is safe — it is a CA
certificate, not a key, and it is the same public value for every Cloudflare
account — but it is worth being explicit that it is not treated as a
secret and does not belong in `.env`.

## Alternatives considered

**Cloudflare IP range allowlist in Caddy.** Restrict the site block to
Cloudflare's published IP ranges with a `remote_ip` matcher instead of
verifying a certificate. Rejected: Cloudflare's ranges change occasionally,
which would need to be watched and the Caddyfile updated by hand; a
certificate check has no such maintenance burden and is what Cloudflare
built this feature for.

**Skip origin lockdown, just trust `CF-Connecting-IP`.** Rewrite
`X-Forwarded-For` from it without verifying the request came through
Cloudflare at all. Rejected: a client hitting the origin directly can set
that header to anything it likes, turning a rate limiter that is merely
keyed on the edge into one any client can dodge by picking a new value per
request — worse than doing nothing, while looking like a fix.

**Zone-level or per-hostname Authenticated Origin Pulls**, uploading a
certificate specific to this Cloudflare account instead of using the shared
global one. Rejected for now per the Decision section above — nothing here
depends on distinguishing this Cloudflare zone from another, so the extra
certificate management isn't earning its cost yet.
