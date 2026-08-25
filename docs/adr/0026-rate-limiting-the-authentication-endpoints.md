# 0026. Rate limiting the authentication endpoints

Date: 2026-08-21

## Status

Accepted.

## Context

A security audit run against the live deployment on 2026-08-21 found
`/auth/register` and `/auth/login` reachable with no request limit of any
kind. Both are on the public internet and unauthenticated by definition —
that is what they are for — and each has a real cost per call:
`/auth/register` writes two rows (`AuthController.java`, `register`), and
`/auth/login` runs a bcrypt comparison at the strength
`SecurityConfig.passwordEncoder()` sets (line 64, default strength 10),
which is deliberately slow. A caller with no rate limit can drive either
cost as fast as the network allows: `/auth/register` as an unbounded write
amplifier, `/auth/login` as a CPU amplifier tuned by the same strength that
makes a stolen hash expensive to crack.

The service runs as a single instance (ADR 0006) behind Caddy, reached over
the Docker bridge network. `request.getRemoteAddr()` as seen by the app
container is therefore the bridge address for every caller unless the
server is told to trust `X-Forwarded-For`, which `server/Caddyfile`'s
`reverse_proxy` already sets. That header is load-bearing for any IP-keyed
limiter and has to be wired deliberately rather than assumed.

## Decision

An in-process filter, keyed on client IP, applied only to `/auth/**`.

`AuthRateLimitFilter`, an `OncePerRequestFilter` registered in
`SecurityConfig` ahead of `JwtAuthFilter` (`SecurityConfig.java:45`), holding
a bounded in-memory map of IP to a fixed-window or token-bucket counter.
Roughly 10 requests per minute per IP against `/auth/login` and
`/auth/register`, answering 429 with a `ProblemDetail` body and a
`Retry-After` header once exceeded. The map is kept bounded — evicted on a
schedule or capped in size — so the filter added to prevent a resource
exhaustion attack does not become one itself.

`server.forward-headers-strategy=framework` is set in
`application.properties` so `getRemoteAddr()` resolves from
`X-Forwarded-For` rather than the bridge address, which would otherwise
throttle every caller as a single client.

This is a single-instance, in-memory decision. It stops working as a limiter
the moment there are two `app` containers, because each keeps its own
counters and a caller can double their effective budget by chance of which
process answers. That is noted here so scaling past one instance is the
trigger to revisit this ADR, not something that silently stops enforcing
while looking unchanged.

**Amended by ADR 0029.** The *Alternatives considered* section below named
Caddy-layer rate limiting as the better answer "once the app is proxying to
more than that one filter's concern." That second concern arrived — the
Catalogue's public search, cover and download endpoints — before a second
`app` instance did. Rather than standing up a proxy-layer limiter early, ADR
0029 extends this same filter with per-path budgets. The trigger for moving to
Caddy-layer limiting stays a second `app` instance, unchanged by this
amendment; only the fact that the predicted second concern has now arrived,
and was absorbed here rather than triggering the move, is new.

## Alternatives considered

**Caddy-layer rate limiting.** Not available in the standard `caddy:2`
image; the `caddy-ratelimit` plugin needs a custom build. `app/web.Dockerfile`
is deliberately a single `COPY` onto the stock image (see its own header
comment on why the build happens on the CI runner rather than in the
image), and a plugin would turn a config change into a second image to
build and keep in step with upstream Caddy releases. Rejected for the
weight, not for being wrong — it is the better answer once the app is
proxying to more than this one filter's concern.

**Bucket4j.** A correct, well-tested token-bucket library. Rejected for
now as a new dependency for what a single instance can do with a map and a
scheduled eviction — this rejection is contingent on staying single-instance,
noted above. A second `app` container makes per-process counters wrong in
a way Bucket4j with a shared store (e.g. backed by the same Postgres, or
Redis) solves and an in-process map cannot. That is the point at which this
decision is revisited rather than patched.

**Nothing, on the grounds that this is a portfolio project.** Rejected: the
service is on the public internet today, `/auth/register` is unauthenticated
and writes two rows per call, and bcrypt makes `/auth/login` a real CPU
amplifier at the configured strength. The cost of the filter is small and
the exposure is live, not hypothetical.

## Consequences

A legitimate reader who mistypes a password repeatedly, or a device that
retries a failed registration in a loop, can be throttled by the same limit
that stops an attacker — the filter cannot distinguish intent, only rate.
Ten requests per minute is generous enough that normal use is not expected
to hit it; if it does in practice, the number is revisited rather than the
mechanism.

The bounded map adds a small, constant amount of memory to the `app`
container proportional to the number of distinct IPs seen in the eviction
window, not to total request volume.

## Verification

Built in the PR implementing this decision (part of #128). `AuthRateLimitFilter`
is an `OncePerRequestFilter` registered ahead of `JwtAuthFilter` in
`SecurityConfig`, matching requests under `/auth/**` by servlet path and
counting them per `getRemoteAddr()` in a fixed one-minute window, held in a
bounded `ConcurrentHashMap` evicted every five minutes. The limit is
configurable (`AUTH_RATE_LIMIT_PER_MINUTE`, default 10) so tests can raise or
lower it without touching production behaviour.

`AuthRateLimitFilterTest` runs against a real embedded server
(`webEnvironment = RANDOM_PORT`), not `MockMvc`, because `X-Forwarded-For`
translation only happens in the servlet container's own `ForwardedHeaderFilter`,
which `MockMvc`'s `webAppContextSetup` never invokes. With the limit overridden
to 2 for that test class: a third `/auth/register` from the same IP in one
window gets 429 with a `Retry-After` header, and a request carrying a
different `X-Forwarded-For` still succeeds — proving the forwarded-header
wiring this ADR called load-bearing, not just the counter.

`./mvnw --batch-mode verify` passes with the new filter and test in place; CI
(`app`, `server`, `test (rsvp_engine)`, `test (epub_reader)`) is green on the
PR.

The per-path budgets ADR 0029 adds for the Catalogue's search, cover and
download endpoints are not built by this verification — that extension is not
yet built at all, and its own PR fills in what was run.
