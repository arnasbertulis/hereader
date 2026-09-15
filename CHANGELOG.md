# Changelog

What each release gives a reader of the app, and what changed on the server.
Versions follow the rules in [CONTRIBUTING.md](CONTRIBUTING.md#releases);
every entry is also published as a
[GitHub release](https://github.com/arnasbertulis/hereader/releases) of the
same tag.

## [Unreleased]

## [0.5.3] — 2026-09-15

Sharing a link to hereader now shows a preview card — the app's name, what it
is for, and an image — instead of a bare address. The repository also gains
this changelog, a code of conduct, and a published release for every version.

## [0.5.2] — 2026-09-15

hereader moves to its own address, hereader.arnasbertulis.com; the old sslip.io
address stops working. Traffic now arrives through Cloudflare, and the server
refuses any connection that didn't, so the sign-in rate limit counts each
visitor on their own instead of everyone behind the same Cloudflare edge
together.

## [0.5.1] — 2026-09-15

A floored word's ORP highlight now lands on the fixation point instead of a
letter the cut keeps out of view, and the word itself clips visibly at the
floor rather than spilling past it. Sliding text measures once per chunk, so
the mid-read pop-in and speed drift are gone; scale-to-fit measures at the
reader's own text scaler instead of assuming one. A background tab no longer
rebuilds on its own timed position saves.

## [0.5.0] — 2026-09-11

Settings gets a faster path to the active reading profile's editor, and the
tap-to-pause gesture is now taught on first Play instead of assumed. Home,
Library and the note editor trim their prose to ADR 0036's budget, and the
sliding-window scroll measurement now sizes by pixels instead of tokens,
fixing drift on tall screens.

## [0.4.1] — 2026-08-31

Firefox readers were getting drift's own storage-tier and missing-feature
messages printed to their browser console on every load: drift_flutter's
`driftDatabase()` falls back to its default `onResult` handler when none is
supplied, and that handler prints unconditionally. Firefox lacks the browser
features drift's preferred OPFS tier needs and falls back to `sharedIndexedDb`
— a supported tier, not a failure — so this fired for every Firefox reader in
production. Gated behind debug mode; still visible when developing locally.

## [0.4.0] — 2026-08-31

Free books: search Project Gutenberg's roughly 78,000 public-domain titles by
title or author, browse by category or language, sort by title, author, issue
date or popularity in either direction, and import with one tap.

The catalogue is ingested from Gutenberg's bulk exports and searched from the
service's own copy rather than proxied live, refreshed weekly. Book files
stream through the service without being retained there; covers are proxied
the same way but cached on disk. A catalogue import gets the same id on every
device it is imported on, so its reading position syncs without the file ever
moving. Recorded in ADR 0029.

Also: a load-more failure on the Free books grid no longer drops what was
already loaded, the conflict sheet now counts tokens rather than the last
index when reporting progress, and byLastRead breaks ties by whether the book
has been read.

## [0.3.1] — 2026-08-24

A hardening pass across the service, the web bundle and the Android build.
The web bundle is now served with a Content-Security-Policy, security headers
and HSTS, and a missing asset returns 404 instead of the app shell. The sync
payload cap measures the encoded JSON rather than a `Map.toString()`, a null
entity type is refused with 400 rather than failing with 500, CORS no longer
allows credentials it never needed, and two redundant indexes and an
unenforced conflict constraint are corrected.

The EPUB reader bounds a zip's entry count and declared uncompressed size
before inflating it. On Android, the reading database is kept out of
auto-backup, release builds are signed from the environment, and the launcher
carries the app's name. A security policy is published and CodeQL now scans
every change.

## [0.3.0] — 2026-08-21

Signing in got harder to abuse. Signing out now revokes the refresh token on
the server rather than only forgetting it on the device (ADR 0027), and the
authentication endpoints are rate-limited (ADR 0026). A login takes the same
time whether or not the email exists, request validation the controllers
already declared is now actually run, the public API stops over-sharing and
over-accepting, and production CORS is pinned to the deployed origin.

Android release builds declare the network permission, so they can reach the
service at all. Both colour screens now share one RGB picker, and the app's
own test suite runs in a real browser before a release is deployed.

## [0.2.0] — 2026-08-20

Continuous-scroll reading, and a nightly database backup.

The second reading surface: text slides past a fixed eye point instead of
being replaced word by word, chosen per profile and drawn by the same resolver
the fixed anchor uses, so a contrast guard cannot measure a pair nothing
paints. Recorded in ADR 0025.

Alongside it, the chapter panel now opens on the chapter being read, a note's
date reaches a screen reader, and a rewind on resume of none no longer moves
the reader to the leading edge of the word they stopped in.

On the server, Postgres is backed up nightly by its own compose service, and
the restore has been run rather than assumed.

## [0.1.0] — 2026-08-19

First release deployed by the pipeline rather than by hand.

Covers everything through the deployment change: the service and the web
bundle built into container images by CI and pulled by the server, over a key
restricted to the deploy script.

[Unreleased]: https://github.com/arnasbertulis/hereader/compare/v0.5.3...HEAD
[0.5.3]: https://github.com/arnasbertulis/hereader/releases/tag/v0.5.3
[0.5.2]: https://github.com/arnasbertulis/hereader/releases/tag/v0.5.2
[0.5.1]: https://github.com/arnasbertulis/hereader/releases/tag/v0.5.1
[0.5.0]: https://github.com/arnasbertulis/hereader/releases/tag/v0.5.0
[0.4.1]: https://github.com/arnasbertulis/hereader/releases/tag/v0.4.1
[0.4.0]: https://github.com/arnasbertulis/hereader/releases/tag/v0.4.0
[0.3.1]: https://github.com/arnasbertulis/hereader/releases/tag/v0.3.1
[0.3.0]: https://github.com/arnasbertulis/hereader/releases/tag/v0.3.0
[0.2.0]: https://github.com/arnasbertulis/hereader/releases/tag/v0.2.0
[0.1.0]: https://github.com/arnasbertulis/hereader/releases/tag/v0.1.0
