# 0027. Refresh-token revocation is a token_version column, checked at refresh

Date: 2026-08-21

## Status

Accepted.

## Context

Issue [#113](https://github.com/arnasbertulis/hereader/issues/113), found in
the same 2026-08-21 audit that produced #128's stack. Refresh tokens are
60-day stateless JWTs (`TokenService.java:55-57`, `JWT_REFRESH_DAYS` default
60) with no revocation path anywhere in the server. `ApiClient.logOut()`
(`api_client.dart:89`) — currently dead code; `AccountScreen._signOut`
(`account_screen.dart:58`) calls `api.auth.clear()` directly — clears local
storage only. A refresh token captured before sign-out, or simply leaked, is
usable against `/auth/refresh` for up to 60 days regardless of what the
account holder does on their own device.

Two designs were weighed, both from the issue:

- A `token_version` column on `users`, checked when a refresh token is
  presented. One column, one comparison. Bumping it invalidates every
  refresh token issued for that user at once, on every device.
- Rotation with a stored-jti reuse-detection table: each refresh issues a new
  token and marks the previous jti used; presenting a used jti again signals
  theft and revokes the chain. Detects theft specifically, at the cost of a
  new table and a write on every refresh.

## Decision

A `token_version` bigint column on `users`, default 0 (`V4__token_version.sql`).
Every refresh token carries the version it was issued under, as a `ver` claim
alongside the existing `typ` claim. `POST /auth/refresh` looks up the user's
*current* `token_version` and rejects the token if it does not match. A new
`POST /auth/logout`, authenticated by the caller's access token, increments
the column.

**Access tokens do not carry or check a version.** `JwtAuthFilter` verifies
every authenticated request today with no database read at all — it is pure
signature and claim verification. Checking `token_version` there would mean a
database round trip on every request in the app, for the entire deployment,
to close a window that access tokens already close on their own by expiring
within `JWT_ACCESS_MINUTES` (default 60). Revocation here means: no *new*
access or refresh tokens can be minted from that refresh token, from the
moment of logout. An access token already in a caller's hand keeps working
until it expires on its own, at most an hour later by default. That is the
trade this ADR makes deliberately, not an oversight — see Consequences.

`AccountScreen._signOut` is changed to call `ApiClient.logOut()` instead of
`api.auth.clear()` directly, and `logOut()` is changed from clearing local
storage only to calling `POST /auth/logout` first (best-effort — a network
failure or an already-invalid access token still falls through to clearing
locally, since from the device's own point of view signing out succeeds
either way).

## Alternatives considered

**Rotation with stored-jti reuse detection.** Rejected for now, not as
wrong: it is the design that actually detects theft, where a version bump
only ever revokes deliberately, on a logout the account holder chose. A
`token_version` bump cannot tell a stolen token from a legitimate one still
in use — logging out revokes every device at once, including ones the reader
meant to keep signed in. Revisit this the moment the requirement becomes
*detecting* a stolen refresh token being used concurrently with the
legitimate one, rather than *letting the reader revoke on demand* — that is
a different problem and rotation is the design for it, not this one.

**Checking `token_version` on every access-token request too.** Rejected: it
would put a database read on the hot path of every authenticated request in
the app, for a window `JWT_ACCESS_MINUTES` already bounds on its own. Kept
open as a call to revisit if the access-token lifetime is ever raised
substantially, since the two are the same trade at different time constants.

## Consequences

Logging out on one device signs every device out — there is no per-device
granularity, so a reader meaning to end a session on a lost phone while
staying signed in on a laptop cannot do that with this endpoint alone.
Acceptable for what #113 asked for: a way to actually revoke, not selective
revocation.

An access token already issued remains usable for up to `JWT_ACCESS_MINUTES`
(default 60 minutes) after logout, even though no new one can be minted.
Stated here so it is never read as "instant" revocation later.

`POST /auth/refresh` now costs one extra `SELECT` against `users` by primary
key, on top of the existing `EXISTS` check it replaces — no material change
in cost, and refresh is not in the same amplifier category PR3/PR4 of #128
addressed (login and register).

## Verification

`server/src/test/java/lt/hereader/server/auth/AuthControllerIntegrationTest.java`:
a refresh token obtained before `/auth/logout` is rejected by `/auth/refresh`
afterward; `/auth/logout` without a bearer token answers 401.
`server/src/test/java/lt/hereader/server/auth/TokenServiceTest.java`:
the `ver` claim round-trips through `issueRefreshToken`/`refreshTokenInfo`,
and an access token is not accepted where refresh-token info is asked for.
`./mvnw --batch-mode verify` passes. Built in the PR implementing this
decision (part of #113).
