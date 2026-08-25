# 0029. The Catalogue is ingested from bulk exports and searched locally, not proxied

Date: 2026-08-25

## Status

Accepted.

## Context

A reader who wants something to read has to leave the app: find a public-domain
EPUB in a browser, download it, come back, and hunt for it in a file picker.
The Library's add menu has no answer to "I would like a book and do not have
one." Project Gutenberg is the obvious source — public domain, no licensing
question — but its data can be reached in three different ways, and which one
answers a reader's keystroke is the decision this record makes.

**Cold-query latency was measured, not assumed**, against Gutendex, the usual
third-party JSON wrapper around Gutenberg's data: **18.3 s, 19.3 s, 31.1 s and
36.9 s**, dropping to 0.11–0.26 s only once a shared CDN cache was warm. A
cache in front of it does not help a reader searching an unusual author, since
the response has to be fetched once before it can be cached, and that one
fetch is exactly the request on the critical path. Gutenberg's own catalogue
search endpoint answered far better — **0.58 s, 0.60 s, 0.58 s**, no cache
dependency — but still puts a third party in the path of every keystroke, and
limits filtering and counting to whatever a feed returns per query.

Gutenberg also publishes two bulk exports. The catalogue CSV carries id, type,
issue date, title, language, authors, subjects, LoC classification and
bookshelves for **79,252 records, 78,001 of them of type Text**, in a 21 MB
file. The bulk RDF export carries a download count per book and is **185 MB
compressed, 2.0 GB unpacked**.

The app's web build is served from `server/Caddyfile` under a
`Content-Security-Policy` (ADR 0028) and a `Cross-Origin-Embedder-Policy`, both
scoped to the app's own origin, and Gutenberg sends no
`Access-Control-Allow-Origin` on either its EPUB or its cover files. Any design
that has the client fetch Gutenberg directly has to survive all three at once,
and the deployed target is where that has to hold — not a build without the
same headers.

## Decision

### The Catalogue lives in Postgres, ingested from the two bulk exports

Reader-facing search runs entirely against the service's own copy of the
catalogue. It never makes an outbound call, so a volunteer archive being slow
or unreachable cannot make the app's own search look broken.

Only Text records become Catalogue Entries — the CSV's other types are audio,
images and datasets, none of which produce something the app's EPUB parser can
open. Popularity is read from the RDF export's download counts and is
**streamed**, entry by entry, with everything but the count discarded: decoding
the whole 2.0 GB to disk first would need scratch space this VPS does not have
to spare, and the uncompressed tar already sits within a megabyte of the 2 GiB
boundary a streaming reader is indifferent to and a size-declaring one is not.
The two exports join on the Gutenberg book number — the CSV's identifier
column, and the tail of the RDF record's subject URI. No fuzzy matching.

Ingesting into real columns, rather than passing through whatever an API
happens to return per call, is also what makes filtering by category and
counting a category affordable — a browse control the Catalogue needs and a
proxied search cannot cheaply give it.

### A refresh is one transaction, weekly, triggerable by hand as a host job

Upsert every row, delete what vanished upstream, commit — a reader searching
mid-refresh sees the old Catalogue or the new one, never a blend. Weekly,
because a volunteer archive does not move at the pace of a news feed. The
manual trigger is a job invoked on the host, the same way the nightly database
backup (ADR 0024) already runs, rather than an HTTP endpoint — the service has
no roles, so an endpoint would let any authenticated caller start a 185 MB
re-ingest on a 4 GB machine.

### Book files and covers stream through the service and are retained nowhere

Both are fetched from Gutenberg on demand and written straight to the
response; nothing is written to disk or to a column. The download endpoint
accepts only book numbers already present in the ingested Catalogue, which is
what keeps it from being a general-purpose proxy: it cannot be pointed
anywhere that has not already been ingested. Covers are cached on a bounded
disk volume with a long client-side cache lifetime, since a cover is immutable
for a given book; ingesting all ~78,000 covers ahead of use was rejected at
roughly 1.5 GB for images a reader will look at a few dozen of, and storing
them in Postgres was rejected because they would land in every nightly backup
for data refetchable in milliseconds.

### The client cannot fetch Gutenberg directly on the deployed web build

Three independent blocks, any one of which is sufficient on its own:

1. The web build's `Content-Security-Policy` (ADR 0028) sets `connect-src
   'self'`, so a fetch to any other origin is refused by the browser before a
   request is even sent.
2. The same build's `Cross-Origin-Embedder-Policy` requires a cross-origin
   subresource to opt in via CORP or CORS before the page is allowed to use
   it.
3. Gutenberg sends no `Access-Control-Allow-Origin` header on its EPUB or
   cover files, so even a policy that permitted the connection would still
   have the browser refuse to expose the response body to script.

A redirect does not sidestep any of these: a CSP and a COEP are both
re-evaluated against the redirect's final target, not the URL the request was
made to, so a same-origin proxy redirecting to Gutenberg fails the same way a
direct cross-origin fetch would.

### Catalogue endpoints are public and rate limited

Browsing free public-domain books does not need an account, so search, cover
and download are exempted from the authentication the rest of the API
requires. They extend the existing per-IP rate-limit filter (ADR 0026) with
per-path budgets rather than moving to a proxy-layer limiter — see that ADR's
amendment below.

## Alternatives considered

**Proxy Gutendex, the third-party JSON wrapper.** Rejected on the measured
cold-query latency above: 18–37 s, and a cache cannot help a query nobody has
asked yet, since the first fetch is the one on the critical path.

**Proxy Gutenberg's own catalogue search endpoint.** Genuinely viable at
0.58 s and a fraction of the implementation work. Rejected because it keeps a
third party in the path of every search and limits filtering and counting to
whatever a single feed query returns — exactly the part of this feature most
likely to grow (category counts, language filters, sort orders).

**Let the client fetch Gutenberg directly.** Impossible on the deployed web
build for the three independent reasons above. Viable on native, which raised
the next alternative.

**A native-direct, web-proxied split**, fetching from Gutenberg directly on
Android/Windows and through the service only on web. Rejected: it is two code
paths carrying one fact, and the path that would get developed and exercised
day to day is the one production — the deployed web build — never runs. A
divergence between the two would be found on web, in production, rather than
in a native build on a developer's machine.

**Unpacking the RDF archive to disk before parsing.** Rejected: roughly 2.0 GB
of scratch space per refresh, on a VPS with no room to spare for it, against a
streaming parse that needs none.

## Consequences

The Catalogue can drift from Gutenberg between refreshes — a book added or
removed upstream is not reflected until the next weekly run, or a manual one.
Accepted: a volunteer archive does not change fast enough for a week's staleness
to matter to a reader browsing it.

A Catalogue Entry that vanishes upstream is deleted rather than tombstoned.
Nothing in the app refers to a Catalogue Entry — a reader who already imported
the Book keeps it, because Books live on the device (ADR 0004) — so there is
nothing downstream for a tombstone to protect.

The service now proxies file bytes it never chose to host, for a source it
does not control the availability of. If Gutenberg is unreachable, search still
answers from the local Catalogue, but the download and cover endpoints fail
until it recovers — a partial-availability mode the app has to show plainly
rather than as a generic error.

## Verification

Not yet built. This record opens the implementation stack tracked in #173
(#175–#182); the last item in that stack, #183, fills in this section with the
commands that were actually run once the Catalogue exists to run them
against.

## Amendments to existing records

### ADR 0004 — streaming an unretained public-domain file is not relaying a reader's library

ADR 0004's *Consequences* section reasons that relaying book files through the
service "would make this project a service that transmits copyrighted
content, which is exactly what storing them on-device avoids." That reasoning
is about a reader's own library, which is not this project's to redistribute
and is frequently still under copyright. It does not extend to a Gutenberg
import: the text is public domain, the service never chose to host a copy of
it, and nothing is retained once the response finishes. Amended in place in
that file, alongside this decision, so the two records do not read as
contradicting each other.

### ADR 0026 — the second concern it anticipated has arrived

ADR 0026's *Alternatives considered* named Caddy-layer rate limiting as "the
better answer once the app is proxying to more than that one filter's
concern," and its *Decision* section named a second `app` instance as the
trigger for revisiting the whole approach. The Catalogue's public search,
cover and download endpoints are that second concern, arriving before a second
instance did. Rather than standing up a proxy-layer limiter early, this record
extends the existing per-IP, in-process filter with per-path budgets — search,
covers and downloads get different limits, because one flick of a browse grid
is dozens of cover requests where ten downloads a minute is already generous.
The trigger for moving to Caddy-layer limiting stays a second `app` instance,
unchanged by this amendment; that file is amended in place to record that the
concern it predicted arrived and was absorbed rather than triggering the move.
