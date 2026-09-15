# 0039. Front the origin with Cloudflare, verified by Authenticated Origin Pulls

Date: 2026-09-16

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
VPS with the right `Host` header. Doing so also defeats
[`RateLimitFilter`](../../server/src/main/java/lt/hereader/server/config/RateLimitFilter.java):
it keys off `request.getRemoteAddr()`, resolved from `X-Forwarded-For` via
`server.forward-headers-strategy=framework`
(`.claude/rules/server.md`). Caddy's default behaviour is to *append* the
connecting IP to whatever `X-Forwarded-For` a client already sent rather
than replace it, and Spring resolves the remote address from the leftmost
entry — so a direct client can already forge its own rate-limit identity
today, Cloudflare or not, simply by sending its own `X-Forwarded-For`
header.

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
signal: Cloudflare sets it from its own edge connection and strips any
client-supplied copy before doing so, and now only Cloudflare can complete a
TLS handshake with this origin at all. `reverse_proxy` in the `/api/*`
block overwrites `X-Forwarded-For` with `CF-Connecting-IP` before proxying
to the app, closing the forgery gap above rather than trusting a header a
direct client could still set for itself.

The global (account-wide) variant of Authenticated Origin Pulls is used
rather than the zone- or hostname-level variant that lets an account upload
its own certificate — the global certificate is shared across all Cloudflare
accounts, so it proves "this came through some Cloudflare zone," not
specifically this one. That's sufficient here: the goal is closing the
direct-to-origin bypass, not distinguishing this Cloudflare zone from
another. A stricter per-zone certificate is available later without
changing this decision if that distinction ever matters.

## Consequences

Cloudflare's SSL/TLS encryption mode must be **Full** or **Full (strict)**
in the dashboard — Authenticated Origin Pulls requires it, and neither this
repo nor CI can set that; it's a manual step alongside the DNS record and
the Authenticated Origin Pulls toggle itself (both under SSL/TLS → Origin
Server in the Cloudflare dashboard).

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

**Skip origin lockdown, fix only the rate-limit header.** Trust
`CF-Connecting-IP` for rate limiting without verifying the request came
through Cloudflare at all. Rejected: `CF-Connecting-IP` is only
trustworthy because Cloudflare controls it — a client hitting the origin
directly can set that header to anything it likes, making this strictly
worse than the status quo rather than better, since it would look like a
fix while remaining just as forgeable.

**Zone-level or per-hostname Authenticated Origin Pulls**, uploading a
certificate specific to this Cloudflare account instead of using the shared
global one. Rejected for now per the Decision section above — nothing here
depends on distinguishing this Cloudflare zone from another, so the extra
certificate management isn't earning its cost yet.
