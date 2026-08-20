# Hereader

![dart](https://github.com/arnasbertulis/hereader/actions/workflows/ci-dart.yml/badge.svg?branch=main) ![flutter](https://github.com/arnasbertulis/hereader/actions/workflows/ci-flutter.yml/badge.svg?branch=main) ![java](https://github.com/arnasbertulis/hereader/actions/workflows/ci-java.yml/badge.svg?branch=main)

A configurable reading surface. Text is presented one word at a time in a fixed position, instead of as a page you scan with your eyes.

**Status: in active development.** Books can be imported and read, notes can be written and read alongside them, reading settings can be adjusted and saved, and both a reading position and the settings themselves follow the reader between devices. Live at **[https://204-168-240-12.sslip.io](https://204-168-240-12.sslip.io)** — open it directly in a browser, or see [Current state](#current-state) for what works today.

---

## Why this exists

Conventional page reading assumes you can move your eyes efficiently across a line of text. That assumption fails for a lot of people, and the clearest case is **central field loss**, where a blind spot sits in the middle of the visual field. Reading a page then means repeatedly locating the next word using an off-centre part of the retina.

Presenting one word at a time in a fixed position removes that search. Rubin and Turano (1994) confirmed the mechanism directly with retinal imaging: readers with dense central scotomas made about 1.3 fewer saccades per word under rapid serial visual presentation (RSVP) than when reading a page.

Central field loss is the case that prompted this project. It is not the only one the app targets. Presentation is exposed as a set of independent controls, so different needs configure it differently: print size, position on screen, pacing model, chunk size, spacing, contrast polarity, typeface, and whether the reader or a timer advances the text. Named presets set starting points, and every value stays adjustable afterward.

---

## What the research says

Full notes, including the studies that argue against this design, are in [`docs/research/rsvp-evidence.md`](docs/research/rsvp-evidence.md). Summary:

**RSVP is not a speed-reading technique for normally sighted readers, and this project makes no such claim.** Eye movement is not the bottleneck in reading; language processing is. RSVP also eliminates regressions, the backward eye movements skilled readers use on difficult sentences, and removes parafoveal preview of the upcoming word. Rayner et al. (2016) reviews this in detail.

**For low-vision readers the benefit is real but modest.** Rubin and Turano (1994) found RSVP faster than page reading for both groups they tested, by a factor of about 1.5 for readers with central field loss and about 2.1 for low-vision readers without scotomas. Note the direction: people with central scotomas benefited *less*. The authors concluded that inefficient eye movements account for only part of the reading deficit central field loss causes.

**Two design choices have stronger support than fixed-rate RSVP itself.**

Letting the reader advance each word with a button press rather than watching a timed stream produced reading speeds averaging 47% faster than RSVP among 15 slow low-vision readers, roughly matching their existing CCTV reading aid (Arditi, 1999). Slower readers benefited more, and no benefit was predicted for readers already above 133 wpm under RSVP.

Scaling each word's display duration to its length got readers with central field loss through sentences about 33% faster than a constant rate. Normally sighted older readers in the same study were fastest at a *constant* rate (Aquilante et al., 2001). The same feature has opposite effects in the two groups, which is why pacing is a setting rather than a constant.

These two findings point in different directions and cannot both apply, since reader-elicited advance has no duration to scale. The app ships both as presets and lets the reader decide.

**The evidence does not rank the two ways of showing moving text.** Fine and Peli (1995) found visually impaired observers reading 13% *slower* from one-word-at-a-time presentation than from a scrolling display — a difference that did not reach significance, which is why the paper's own title reports the two as similar rather than picking one. Akthar et al. (2021) compared static text, scrolling text and one-word-at-a-time presentation in central vision loss and found scrolling ahead on *comprehension*, with the one-word format producing high error rates. That is the only comprehension measurement in these notes; everything else is a reading rate. So the app ships both formats and lets the reader choose, rather than choosing on their behalf with nothing to choose on.

**Two things the evidence says not to build.** Vertical text gave no benefit over horizontal RSVP for readers with left-of-scotoma retinal loci (Calabrèse et al., 2017). Increased line spacing does not improve reading speed in AMD patients, despite helping in normal peripheral vision (Chung et al., 2008).

### Not a medical device

This is an accessibility tool. It does not diagnose, treat, manage, or improve any condition, and no claim to that effect is made anywhere in this project. Anyone experiencing a change in their vision should see an ophthalmologist.

---

## Current state

**Working**

- [x] Tokenizer: whitespace splitting, attached punctuation, clause and sentence and paragraph pauses, abbreviation handling, numeric separators and units, line-break hyphen rejoining, Unicode-aware letter counting
- [x] Pacing models: constant, length-scaled, and reader-elicited advance
- [x] Reading profiles: pacing plus presentation settings, JSON round-tripping, forkable built-in presets
- [x] Playback state machine: play, pause, rewind-on-resume, reader-driven advance, seek by character offset, and stop-where-the-reader-chose
- [x] Reader navigation: left and right quarters of the screen step back and forward by a configurable number of words, and buttons jump forward a sentence or a paragraph
- [x] EPUB parsing: zip container, manifest and spine, HTML normalisation into blocks with stable ids, cover extraction
- [x] Front matter detection, so a book opens on its text rather than its licence page — and when the opening position was a guess rather than a marker the book supplied, the reader is told and offered the start of the file
- [x] Reading surface: word anchored per profile, punctuation gaps, keyboard control, reduce-motion support
- [x] Sliding text as an alternative to one word at a time: a single line of the book moves right to left at a steady speed past a marked, fixed eye point, and you drag a finger across the screen to move through the book instead of tapping its edges. A per-profile setting, with a switch in the reader itself. Recorded in [`docs/adr/0025-continuous-scroll.md`](docs/adr/0025-continuous-scroll.md)
- [x] Library: import, list as a grid of covers, open, remove, and resume where you left off after a restart. Sort by title, recency or progress, each field naming its own two ends, and filter to books or notes
- [x] Local notes: write text, read it through the same reading surface a book uses, and edit it afterwards. Stored and parsed like a book rather than through a path of its own, so a note gets the same stable positions. Recorded in [`docs/adr/0017-local-notes.md`](docs/adr/0017-local-notes.md)
- [x] A home screen that opens on the book you were last in, showing its cover, where you are in it, and roughly how long is left at the pacing your active profile is set to. Under reader-elicited advance it says how many words are left instead of a time, because nothing there moves until you press. Recorded in [`docs/adr/0014-reading-time-estimate.md`](docs/adr/0014-reading-time-estimate.md)
- [x] The chapter you are in, on the home and library tiles, beside a time that counts down either to the end of that chapter or to the end of the book — your choice, in Settings. Written down as you read rather than worked out later, because a book is not parsed until it is opened and parsing one to draw a tile is the thing this app cannot afford on the web. Recorded in [`docs/adr/0018-chapter-hint-on-a-tile.md`](docs/adr/0018-chapter-hint-on-a-tile.md)
- [x] Reading positions written while reading, not only on close: on every stop, every fifteen seconds the reader is moving, when the app is hidden, and when the book closes. Recorded in [`docs/adr/0011-position-save-cadence.md`](docs/adr/0011-position-save-cadence.md)
- [x] Chapter navigation: the book's own table of contents in a panel, from the EPUB 3 navigation document or the EPUB 2 NCX, resolved through fragment anchors so scenes sharing one file land in different places
- [x] Settings: copy a preset to make a profile of your own, then change pacing, type size, spacing, position on screen, contrast polarity, background colour and the rest, with a live preview drawn through the reading surface itself and a contrast warning
- [x] Chrome that follows the reading profile: the controls, chapter panel and progress bar drawn over the text take a brightness read from the profile's own background rather than from the platform, so a book set to light on dark keeps dark chrome on a device set to light. Recorded in [`docs/adr/0015-reader-chrome-is-monochrome-over-the-profile.md`](docs/adr/0015-reader-chrome-is-monochrome-over-the-profile.md)
- [x] A reading surface that follows the app where the profile states no preference, so opening a book from a dark home screen does not arrive on white. A profile whose citation picks a surface keeps it. Recorded in [`docs/adr/0016-reader-theme-follows-the-app.md`](docs/adr/0016-reader-theme-follows-the-app.md)
- [x] App appearance: light, dark or whatever the device asks for, six accents plus an arbitrary one, and a high contrast mode that replaces the neutral ramp rather than deepening it. Stored on the device and read before the first frame, so a dark-theme device does not flash white on the way in. Recorded in [`docs/adr/0012-app-chrome-appearance.md`](docs/adr/0012-app-chrome-appearance.md)
- [x] Screen reader support on the reading surface: it announces as a button, activates by double tap, and stays quiet through a playing stream rather than speaking a word four times a second
- [x] Local persistence with drift, including an outbox for changes waiting to sync — native SQLite on Android and Windows, WASM SQLite over OPFS on web
- [x] Sync service: registration, login, token refresh, an append-only event log with per-user sequence numbers, idempotent pushes, hybrid logical clock ordering, and per-entity conflict resolution
- [x] Sync client: hybrid logical clocks in Dart, tokens in the platform keystore, transparent token refresh, an outbox drainer, and sign-in that is offered rather than required
- [x] Profiles sync: a profile made, changed or deleted on one device reaches the others, with deletion travelling as a tombstone so an offline device cannot resurrect it
- [x] A sheet asking the reader which position they meant when two devices diverge
- [x] Positions synced for a book not yet imported on this device are held locally and applied the moment the book is imported, rather than crashing sync or being lost
- [x] A startup failure is shown rather than rendering nothing. Everything the app needs before its first write is awaited before the first frame, so a failure there used to leave a blank page indistinguishable from a hang
- [x] Test suite across all of the above, including a real Project Gutenberg book as a golden fixture, effective words per minute over real prose, virtual-clock playback timing, sync ordering and divergence against a real Postgres, and the sync client against a fake service
- [x] CI running analyzer and tests on every push, across every package, the app, and the service, with the pure packages also run through `dart2js` in a browser and the web build compiled on every change
- [x] Deployed: containerised service and web build behind Caddy on a Hetzner VPS, automatic HTTPS via an sslip.io hostname, with reading positions and profiles both verified syncing between Windows and web against the live service
- [x] CD pipeline: a `v*` tag builds the service and the web bundle into container images, pushes them to GHCR and has the server pull them, over a key that can run nothing but the deploy script. The release running is recorded on the server by commit sha, so rolling back does not need the pipeline. Recorded in [`docs/adr/0023-continuous-deployment.md`](docs/adr/0023-continuous-deployment.md)
- [x] Nightly database backups from a service in the same compose file, checked for readability before they are published and pruned only after a new one lands. A dump older than 25 hours makes the container report unhealthy, because a backup that quietly stopped looks exactly like one that is working. Recorded in [`docs/adr/0024-database-backups.md`](docs/adr/0024-database-backups.md)

**Not started**
- [ ] Running the app's own suite in a real browser. The pure packages run under `dart2js` in CI and the web build is compiled on every change, but the app's tests reach `dart:ffi` through drift and cannot execute on that target. See [`docs/adr/0009-web-platform-coverage.md`](docs/adr/0009-web-platform-coverage.md)

---

## How sync works

The reader's device is authoritative for reading. Everything works with no network, because a reading app that stalls on a dead connection is a broken reading app. An account is offered and never required.

Writes go to the local database and append an event to an outbox, in one transaction: a position that reached disk without an outbox entry would never sync, and an entry without a position would sync a change the device does not have. A sender drains the outbox when there is a connection. The service assigns each accepted event a sequence number that is monotonic per user, and other devices pull everything after the number they last saw.

**Ordering uses hybrid logical clocks.** Wall clocks disagree across devices, so ordering by timestamp can pick the older write. A pure counter orders correctly but loses any relation to real time. An HLC is a millisecond, a counter for writes in the same millisecond, and a device id to break ties. It sorts as a string and never moves backwards, even if the system clock does.

Clients supply their own stamps, so the service does not trust them. A stamp more than five minutes ahead of server time is rejected rather than clamped: rewriting it would break the client's own local ordering, and a device claiming next week would otherwise win every comparison from then on.

**Retries are safe.** Every event carries a client-generated idempotency key, enforced by a unique constraint rather than a check followed by an insert, so a push resent after a lost response cannot apply twice under concurrency. An event the service refuses outright counts against a limit and is eventually parked, so one bad event cannot block everything queued behind it.

**Conflict resolution differs by entity, which is the substantive decision.** Preferences and profiles take last write wins, because a stale font size costs nothing. Deletions leave tombstones, because a row that vanished entirely would be resurrected by any device that was offline when it happened. Reading positions are different: being dropped in the wrong chapter is the failure a reader actually notices. Two devices within 500 tokens of each other resolve silently; beyond that, the divergence is recorded and the reader is asked which position they meant.

One device moving a long way is not a divergence — that is an afternoon of reading. It takes two devices disagreeing.

**A position can arrive before its book does.** Book files never leave the device, so a position for a book this device has not imported cannot be written straight into local storage — every web client meets this on its first sign-in, since nothing ever transfers a book file. The position is held locally until the matching book is imported, then applied in the same transaction as the import, rather than being dropped or crashing sync. Recorded in [`docs/adr/0007-pending-positions.md`](docs/adr/0007-pending-positions.md).

Recorded in [`docs/adr/0005-sync-event-log.md`](docs/adr/0005-sync-event-log.md).

---

## Design decisions worth knowing

Every substantial decision has an ADR carrying the alternatives that were rejected and why; the [index below](#architecture-decision-records) lists all twenty-five. These are the ones that shape the most code.

**Reading positions are character offsets, never word indices.** A word index shifts the moment the tokenizer changes, which would silently move every saved position in every book — and nobody reports "my bookmark is forty words off", they quietly lose their place. Character offsets index into the text the tokenizer *reads*, not the text it produces, and locators carry a `parserVersion` so future changes can be migrated deliberately. Recorded in [`docs/adr/0002-locator-format.md`](docs/adr/0002-locator-format.md).

**Pacing returns a decision, not a duration.** Reader-elicited advance has no duration; the word waits for input that may never arrive. Encoding that as a zero or sentinel `Duration` would make one value mean two things, and would leave the playback timer armed. `decide` returns a sealed type with `Hold` and `AwaitAdvance` variants, and `Hold` separates how long the word is shown from the gap after it, so the renderer can blank the anchor during a punctuation pause. Recorded in [`docs/adr/0003-pacing-decision-model.md`](docs/adr/0003-pacing-decision-model.md).

**Book files are stored; parsed text is not.** Parsed output is derived data, and a parser change invalidates every cached copy. Keeping the source file means the parser stays the single source of truth and a normalisation improvement applies to books already in the library, at the cost of re-parsing on open — a few hundred milliseconds for a novel, behind a loading indicator. Recorded in [`docs/adr/0004-store-book-files.md`](docs/adr/0004-store-book-files.md).

**A deletion is recorded on the event, not only on the resolved state.** The service keeps both an append-only log and a resolved value per entity. Clients pull the log. A deletion stored only in the resolved state arrives elsewhere as an ordinary write carrying the entity's last payload and the deletion's stamp — the highest stamp in play — so every pulling device writes it back as live while the deleting device keeps its own tombstone. Two devices permanently disagreeing, with nothing logged anywhere. Found by reading the wire contract end to end before attempting a cross-device test, and reachable by neither suite: the Dart tests run against a fake service, and the Java tests had never exercised a deletion because no client had ever sent one.

**Presets are code, and editing one makes a copy.** Each preset is tied to a specific finding in the evidence notes, so a preset edited past recognition would carry a name that no longer describes it, with no tested starting point left to return to. Editing a preset forks it. That keeps presets out of sync entirely — they are code, identical on every device, and nothing stores or transmits them — and whether a profile is built in is derived from the `builtin.` id namespace rather than stored, so a payload arriving over the wire cannot claim to be one. Recorded in [`docs/adr/0008-profile-merge-granularity.md`](docs/adr/0008-profile-merge-granularity.md), which also covers why profiles merge whole rather than field by field.

**Guessed promises are worse than absent ones.** Chapter navigation reads the book's own table of contents and nothing else: a book declaring neither an EPUB 3 navigation document nor an EPUB 2 NCX gets no chapter list, because a list derived from heading blocks would produce running heads, section labels and the licence page's own title in an order the publisher never endorsed. Entries resolve through fragment anchors rather than hrefs alone, since converters routinely chunk a book by act while the table of contents names scenes, and resolving to the document would land all five of them on one word. Recorded in [`docs/adr/0010-chapter-navigation.md`](docs/adr/0010-chapter-navigation.md).

**Front matter is skipped, never removed.** Dropping blocks would shift every block id and invalidate saved positions, and a wrong guess would delete real text with no way back. Detection only reports a suggested opening index. Where that index came from a marker the book supplied it is applied silently; where it came from pattern matching, the reader is told on the first open and offered the very start of the file — index zero rather than a step back, because the app does not know where the text begins and a second guess about how far to rewind would only compound the first.

**Warnings inform and do not block.** The colour picker shows a WCAG ratio and says plainly when it is too low to read comfortably, then lets the reader proceed. Someone with light sensitivity may want low contrast deliberately, and overriding that in an app whose whole premise is configurability would be worse than a warning they can ignore. The fade control works the same way: a crossfade set longer than a word is held would draw two words on top of each other at the anchor, and the setting says so rather than refusing the value. The point in both cases is that nobody arrives there without being told.

**The reading surface is three buttons, and the word is not spoken word by word.** The centre half is the app's primary control — play, pause, and advance under elicited pacing — and announces as a button with a label that follows playback state. The left and right quarters step back and forward, and each says how far it moves, since that is a number set on a settings page the reader cannot see from here. The current word is offered only while the stream is stopped: a reader using RSVP is reading with their eyes, and speech arriving four times a second would fight the visual stream rather than describe it. A word reached by pausing, advancing or rewinding is different — one fact, and one the reader just asked for.

**Chrome over the text is monochrome, and takes its brightness from the profile.** The controls, chapter button, chapter panel, progress bar and front matter notice are all drawn on top of the reading surface. Under a single app theme they were light, so the two central field loss presets — both reverse polarity — put a light panel and light buttons into the visual field of the reader most likely to have chosen reverse polarity to keep bright light out of it. The panels this screen opens now build from the app's own neutral ramp at a brightness read from the reading surface's measured luminance; the buttons drawn straight on the surface take no theme at all, only an ink colour picked from that same luminance. One accent reaches the screen, on the progress fill, and gives way to the ink wherever it cannot clear 3:1 against its own track. Recorded in [`docs/adr/0015-reader-chrome-is-monochrome-over-the-profile.md`](docs/adr/0015-reader-chrome-is-monochrome-over-the-profile.md).

**A profile need not decide what surface it reads on.** `PresentationConfig.polarity` is nullable, and null says the profile states no preference and whoever draws it supplies one from the brightness the app is running in — so opening a book from a dark home screen does not arrive on white. The three presets whose citations pick a surface state it and keep it inside a light app. The engine holds no notion of a platform theme and cannot look one up, so resolution happens in the app, above the widget that paints, and is carried in a type rather than a comment: `ResolvedPresentation` is an extension type whose only constructor is the resolver, and every function that paints takes one. The settings preview and the WCAG readout draw through the same widget, and they have disagreed about the colours on screen before. Recorded in [`docs/adr/0016-reader-theme-follows-the-app.md`](docs/adr/0016-reader-theme-follows-the-app.md).

**A note is a book row, not a second kind of thing.** Note text is stored as UTF-8 in the same column an EPUB's zip goes in, with a `sourceFormat` column deciding how those bytes get parsed. On open it is split into paragraphs, escaped, wrapped in `<p>` tags and run through the *same* HTML normalizer a spine document goes through, so a note's blocks get real, stable ids and the same locator guarantee a book has — which pasted text's single unversioned block never did. Editing rewrites the row through a plain update rather than the import upsert, which would bump the import date on every edit, and whether an edit resets the reader's place is decided by the editor screen, the only place that holds both the old and the new text: a title-only change never touches it. Recorded in [`docs/adr/0017-local-notes.md`](docs/adr/0017-local-notes.md).

**Arithmetic that depends on the compilation target lives in the pure packages.** `dart2js` represents Dart `int` as a JS double and treats `<<` as a 32-bit operation, so hashing and bit manipulation can be exact on the Dart VM and wrong in a browser. This project lost a day to that twice: a 64-bit block-id hash that failed to *compile* for web, and a random draw of `nextInt(1 << 32)` that compiled fine and threw at *runtime*, because the shift evaluates to zero in JavaScript. One needed a build and the other needed a browser, which is why "add web testing" was not one task. Block ids now hash to 32 bits with the multiplication decomposed into shifts, profile id generation moved into the engine, and the pure packages run their suites through `dart2js` in CI while the app's cannot, because they reach `dart:ffi` through drift. Recorded in [`docs/adr/0009-web-platform-coverage.md`](docs/adr/0009-web-platform-coverage.md).

**Profiles are plain data, including their colours.** Presentation settings live in the pure Dart engine rather than the Flutter app, so they serialise, round-trip and test without a widget harness. The cost is that colours are stored as ARGB integers and the app maps them at the boundary, in the one file that also holds the polarity constants, so a colour the app paints and a colour it judges cannot drift apart again. The WCAG maths itself sits in the engine rather than the app: it touches no Flutter type, and keeping it in the app kept it on the only target the browser test run cannot reach.

**Books imported by the reader never leave the device.** Parsing happens on-device. The service stores reading positions, preferences, and metadata only. This is a deliberate privacy and licensing decision, and it is why a book has to be imported on each device that reads it — and why a synced position can arrive for a book that is not there.

### Architecture decision records

| # | Decision |
|---|---|
| [0001](docs/adr/0001-monorepo.md) | Monorepo with separate pure Dart packages, so the reading core carries no Flutter import |
| [0002](docs/adr/0002-locator-format.md) | Locators are `{blockId, charOffset, parserVersion}`, never word indices |
| [0003](docs/adr/0003-pacing-decision-model.md) | Pacing returns a sealed `PacingDecision`, not a `Duration` |
| [0004](docs/adr/0004-store-book-files.md) | Store EPUB source bytes, not parsed text |
| [0005](docs/adr/0005-sync-event-log.md) | Sync is an event log with per-entity conflict rules |
| [0006](docs/adr/0006-deployment-infrastructure.md) | A single Hetzner VPS with Docker Compose and Caddy, over managed platforms |
| [0007](docs/adr/0007-pending-positions.md) | A position for a book this device lacks is held, not dropped |
| [0008](docs/adr/0008-profile-merge-granularity.md) | Profiles merge whole, at per-profile granularity |
| [0009](docs/adr/0009-web-platform-coverage.md) | Web coverage is a build for the app and a browser run for the packages |
| [0010](docs/adr/0010-chapter-navigation.md) | Chapter navigation reads the book's own table of contents, or none |
| [0011](docs/adr/0011-position-save-cadence.md) | Positions are written while reading, not only on close |
| [0012](docs/adr/0012-app-chrome-appearance.md) | App chrome is a neutral ramp plus one accent, chosen per device |
| [0013](docs/adr/0013-progress-token-index.md) | Reading progress is a stored token index, a hint and never a locator |
| [0014](docs/adr/0014-reading-time-estimate.md) | Time left is estimated from the active profile, and withheld under elicited pacing |
| [0015](docs/adr/0015-reader-chrome-is-monochrome-over-the-profile.md) | Reader chrome is monochrome over the profile, with one accent |
| [0016](docs/adr/0016-reader-theme-follows-the-app.md) | The reading surface follows the app unless the profile decides |
| [0017](docs/adr/0017-local-notes.md) | Local notes are book rows parsed through the same normalizer |
| [0018](docs/adr/0018-chapter-hint-on-a-tile.md) | The chapter on a tile is a device-local hint written with the position |
| [0019](docs/adr/0019-icons-are-two-vendored-phosphor-weights.md) | Icons are two vendored Phosphor weights, named by role in one file |
| [0020](docs/adr/0020-reader-driven-navigation.md) | Tap zones step by a device-local amount and stop where the reader chose |
| [0021](docs/adr/0021-back-a-sentence-back-a-paragraph.md) | Back a sentence and back a paragraph are their own jumps, not a reversed step |
| [0022](docs/adr/0022-chapter-jumps-also-suppress-the-resume-rewind.md) | A chapter or front-matter jump suppresses the resume rewind |
| [0023](docs/adr/0023-continuous-deployment.md) | CI builds the images, a version tag deploys them, and the server only pulls |
| [0024](docs/adr/0024-database-backups.md) | Backups are a nightly `pg_dump` from a compose service, kept on the same machine |
| [0025](docs/adr/0025-continuous-scroll.md) | Sliding text is a second reading surface, driven by a ticker and dragged with a finger |

---

## Repository layout

```
packages/rsvp_engine/     Pure Dart. Tokenizer, pacing models, reading
                          profiles, playback state machine, locators,
                          hybrid logical clocks, WCAG contrast maths.
packages/epub_reader/     Pure Dart. Zip container and OPF parsing, HTML
                          normalisation, front matter detection, table of
                          contents parsing, cover extraction.
app/                      Flutter client. Android, Windows, web.
server/                   Spring Boot service. Auth, sync event log,
                          conflict resolution. Postgres via Flyway.
                          Dockerfile, compose.yaml and Caddyfile for
                          deployment.
docs/adr/                 Architecture decision records.
docs/research/            Evidence notes behind the design.
```

Each directory carries its own README with the detail this one leaves out:
[`app`](app/README.md), [`server`](server/README.md),
[`rsvp_engine`](packages/rsvp_engine/README.md),
[`epub_reader`](packages/epub_reader/README.md).
[`CONTRIBUTING.md`](CONTRIBUTING.md) covers the process this repo follows.

---

## Running it

### The sync service

Optional: the app reads perfectly well without it, and only needs it to sync
between devices.

**Via Docker Compose** (recommended — matches what runs in production):

```bash
cd server
cp .env.example .env   # then edit JWT_SECRET and DATABASE_PASSWORD
docker compose up --build -d db app
```

The stack has a third service, `caddy`, which is named here rather than
brought up: it runs the image CI builds from the compiled web bundle, and
its certificate comes from an sslip.io hostname that resolves to the
server's IP, so a local one fails its ACME challenge. See
[ADR 0006](docs/adr/0006-deployment-infrastructure.md).

Flyway applies the schema on first start. `GET /api/health` reports whether
the service can reach its database, not merely whether the process is alive.

**Directly with Maven**, for backend development without rebuilding a
container on every change. Requires JDK 25 and a Postgres.

Note the container name. `compose.yaml` claims `hereader-db` for its own
database, which does not publish a port to the host (see ADR 0006), so a
development container sharing that name would be replaced by one nothing on
your machine can reach — running, correctly named, and unusable. Tests need
their own:

```bash
docker run --name hereader-test-db \
  -e POSTGRES_PASSWORD=dev \
  -e POSTGRES_DB=hereader_test \
  -p 5432:5432 -d postgres:17
```

The service refuses to start without a signing secret, deliberately: a
placeholder that ships in a repository is worse than a service that is down.

```bash
cd server
export JWT_SECRET=$(head -c 48 /dev/urandom | base64)   # any 32+ byte string
./mvnw spring-boot:run
```

```bash
./mvnw verify   # tests need the hereader_test database above
```

### The reading app

Requires the Flutter SDK, which bundles Dart.

```bash
git clone https://github.com/arnasbertulis/hereader.git
cd hereader

cd packages/rsvp_engine && dart test && dart analyze
cd ../epub_reader && dart test && dart analyze
```

```bash
cd app
flutter pub get
flutter run -d windows   # or -d chrome, or a connected Android device
```

Web needs two additional assets that are not generated by any build step:
`sqlite3.wasm` and `drift_worker.js` are committed under `app/web/`, pinned
copies from drift's own releases, since browsers have no native SQLite and
drift runs a WebAssembly build of it instead.

Add an EPUB from the library screen and read it, or write a note and read
that. Books, notes and reading positions persist across restarts. There is
also a paste screen for reading arbitrary text without storing it.

The app expects the service on `http://localhost:8080/api`. Point it
elsewhere at build time:

```bash
flutter run --dart-define=HEREADER_API=https://api.example.com/api
```

The live deployment is built the same way, by CI rather than by hand:

```bash
flutter build web --dart-define=HEREADER_API=https://204-168-240-12.sslip.io/api
```

That exact command is in both `.github/workflows/ci-flutter.yml`, where it
is the compile-time check ADR 0009 asks for, and
`.github/workflows/cd.yml`, where its output is copied into a Caddy image
and deployed.

Serving the web build over plain `http://` on a local network will fail to
start: the browser database drift uses needs a secure context. Use `https://`,
`localhost`, or `adb reverse` from a phone, which counts as localhost.

---

## Known limitations

- Books do not transfer between devices. Reading positions sync, but the file itself has to be imported on each device. Notes do not transfer either: a note is a book row, and book rows stay local.
- A different edition of the same book produces different block identifiers, so a position saved against one edition will not resolve against another. The app says the place could not be found and opens from the start rather than guessing. A content fingerprint on the book record would let it say which of the two it was, and is not implemented.
- Opening a book waits on a sync attempt so the reader never starts from a position that is about to change. A slow connection therefore delays opening, bounded by a fifteen second request timeout.
- A rejected batch counts the attempt against every event in it, not just the one the service objected to. Coarse, but the alternative is pushing events one at a time.
- Position divergence is judged from a token index the client supplies. The service cannot verify it, and a wrong value causes a prompt that was not needed or misses one that was. The locator itself remains authoritative, and the app resolves both candidates locally rather than trusting the hint.
- Duplicate events consume a sequence number that is then skipped, so the log has gaps and `lastSeq` overstates how many events exist. Harmless, since clients ask for everything after a number rather than counting.
- The event log grows without bound. Compaction is not implemented and is not needed at the scale this will see.
- Two devices editing the same profile while apart resolve by last write wins over the whole profile, so one set of edits is discarded rather than merged. Deliberate, and explained above, but it is a real loss when it happens.
- Preference sync runs one way. The client applies preferences arriving from other devices and never sends its own. Nothing currently needs the outbound path — sync bookkeeping and the active-profile pointer are both deliberately device-local — so this is unused capability rather than a gap, and ADR 0005 says so.
- A profile that states no polarity renders differently on two synced devices whose theme modes differ, since theme mode is device-local under ADR 0012. Intended rather than defective, and written down so nobody has to derive it.
- The accent on the reading surface's progress bar falls back to the surface ink wherever it cannot clear 3:1 against its own track, and says nothing when it does. Unlike contrast and fade this is not warn-don't-block: there is no reading for the reader to override, only a colour that quietly is not the one they picked. The accent and the background are set on two screens that know nothing about each other.
- Text colour follows the contrast polarity and is not separately adjustable; only the background can be tinted. A separate ink colour would need another field on the profile and a change to what travels over the wire.
- Showing more than one word per advance, and presentation modes other than a single fixed word, exist in the data model and are not implemented, so neither is offered in settings.
- A note's Added or Edited date is drawn on its library tile and is not announced to a screen reader, so that fact is on screen and nowhere else.
- Animations feel uneven in Chrome on Android. Chrome throttles a page's main thread to sixty frames a second on high refresh rate displays, giving the full rate only to the compositor — to CSS animations and to browser scrolling. Flutter web draws every frame on the main thread and has no compositor path, so its animations are throttled while the phone's panel is still running at 120Hz, which reads as judder rather than as a lower frame rate. It settles once the panel drops back to 60Hz a few seconds after the last touch, which is why it is worst in the moment right after a tap and never appears while a finger is down. Confirmed by running Chrome with `--disable-features=ThrottleMainFrameTo60Hz`, which removes it completely. Nothing in this app can change it: there is no web API for requesting a higher main-frame rate. One-word-at-a-time reading is unaffected: a word is replaced at a fixed position rather than animated, and its timing comes from a timer rather than a frame callback. **Sliding text is affected, and it is the first thing in this app that animates every frame.** In practice it does not judder: a 60Hz panel matches what `requestAnimationFrame` delivers, and a 120Hz Android panel drops back to 60 a few seconds after the last touch, which aligns for the same reason. What has not been done is a frame measurement on a physical device — see [ADR 0025](docs/adr/0025-continuous-scroll.md), whose Verification section says so rather than claiming a number.
- The deployed web build is compiled without `--wasm`, so it runs the `dart2js` output against CanvasKit rather than the WebAssembly renderer. Caddy already sends `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy`, so the page is cross-origin isolated and a `--wasm` build would get the multi-threaded renderer with raster off the main thread; drift's `sqlite3.wasm` and its worker want testing under that build before it becomes the default. It would be a real gain in main-thread headroom and is *not* a fix for the frame throttle above, which gates the main frame regardless of where raster runs.
- `compute()` does not spawn an isolate on Flutter web. It runs the callback synchronously on the main thread wrapped in a `Future`, so EPUB parsing and tokenizing block the interface during import on that target, unlike Android and Windows where the work genuinely moves off the main thread. Documented rather than solved; a real fix means a web worker.
- The app's own tests run on the Dart VM only, and cannot run anywhere else: they build their database through drift's native backend, which reaches `dart:ffi`. The pure packages do run under `dart2js` in a browser, and the web build is compiled on every change, so a compile-time web break cannot merge. A *runtime* `dart2js` bug in app code still can. Both bugs of that kind so far — a 64-bit hash, and a random draw with a bit shift — would now be caught, but only because the arithmetic in question lives in the pure packages, which is a rule rather than a guarantee.
- Every book open re-parses the file, which takes a few hundred milliseconds for a novel. Caching parsed blocks keyed by parser version is the fix if this becomes a problem.
- Book bytes live in a database column. Fine for text, less comfortable for a heavily illustrated volume of tens of megabytes.
- Front matter detection uses an explicit marker where a book provides one, and pattern matching otherwise. The pattern path is a guess, capped at fifteen percent of a book and never destructive, and the reader is told and offered the start of the file when it was used — but it can still skip a dedication that looks like a rights line.
- Tables, images, figures and MathML are dropped rather than flattened. Reading a table cell one word at a time loses what made it a table.
- The tokenizer reads `Chapter 3.` as a sentence end. Telling list numbering apart from sentence terminators needs context the current design does not carry.
- The abbreviation list is English-only, while the numeric suffix list defaults to Lithuanian and metric units. Both are constructor parameters on `Tokenizer`, so a per-language set can be supplied, but nothing selects one automatically yet.
- A date that genuinely ends a sentence, such as `įvyko 2005 m.`, loses its sentence pause, because the unit is treated as an abbreviation rather than a terminator. Same ambiguity as `e.g.`, and unsolvable without more context than the tokenizer carries.
- The time remaining on the home screen is an estimate, and reads a few percent short. It multiplies the words still ahead by how long one word of reference length is held, and cannot add the punctuation pauses a real run inserts, because which words those follow is a property of the parsed book and books are not parsed until they are opened. It also moves when the reader retunes their profile, which is correct and looks abrupt.
- The chapter on a tile is the one this device last wrote down while reading, so a book whose place arrived from another device shows no chapter, and a time counting the whole book, until you read a little of it here. It is not wrong, but it looks like the chapter disappearing.
- A book that declares no table of contents never shows a chapter on a tile, and neither does a note. Both fall back to the whole-book time, which reads correctly and gives the reader no way to tell that apart from the feature being absent — the same gap the chapter button has.
- A chapter written down before a `kParserVersion` change names a token index that has moved, so the chapter-scoped time can be wrong until the next save overwrites it. Bounded the same way the progress readout is: it is a display hint and nothing navigates by it.
- Length-scaled pacing normalises against a fixed reference word length, so the configured words-per-minute is only accurate on average. Text whose mean word length differs sharply from English will read faster or slower than the setting says.
- The fade warning measures against that same reference hold, so under length-scaled pacing short words begin overlapping slightly before the warning appears.
- The timer chain schedules each word when the previous one finishes rather than against an absolute schedule, so lateness compounds across a book. Probably under a percent and unmeasured — and not measurable by the current tests, which run under a virtual clock that fires every timer exactly on time by construction.
- Pausing mid-word restarts that word's full duration on resume rather than preserving the remainder. The difference is a few hundred milliseconds and was not judged worth the bookkeeping.
- The optimal recognition point highlight is offered as a preference with no evidence behind it. None of the studies above tested it.
- iOS is untested. The codebase targets it, but building and signing requires macOS hardware.
- Flutter web renders text to canvas rather than DOM, so screen reader support on the web target is weaker than a conventional website even where the semantics are correct. There is also no keystore there, so tokens fall back to local storage.
- The web page paints its loading background from the browser's own light or dark preference rather than from the theme the reader chose in the app. That choice lives in the browser's database, behind the engine the page is still loading, so a reader who set Light on a dark-preference device sees a dark background for the moment before the first frame.
- The deployed database is backed up nightly, and every copy is on the same machine as the database. That covers a bad migration, a wrong `DROP` and a deleted data volume; it does not cover losing the server, or a `docker compose down -v`, which takes the dumps with it. An off-box copy is deferred rather than overlooked — it needs a second credential on the server and a destination that costs money, against data whose loss means re-registering test devices. See [ADR 0024](docs/adr/0024-database-backups.md).
- Deploys run from a `v*` tag rather than from a merge, so landing a change on `main` does not ship it. That is deliberate — see [ADR 0023](docs/adr/0023-continuous-deployment.md) — but it does mean the deployed site can sit behind `main`, and nothing reports the gap.
- The deploy pipeline has a health check and no automatic rollback. A release that fails it stays up and fails the workflow; putting the previous one back is a line edited in `server/.env` and a `docker compose up -d` over SSH.
- A position for a book not yet imported on a device is held locally rather than lost. It stays held forever if the reader never imports that book on that device; harmless, since each held position is a locator and two integers, and sign-out clears them.
- The supporting research is small-sample and predates modern displays. Rubin and Turano tested 23 people in 1994; Arditi tested 15 in 1999. These are the best available comparisons, not large trials.
- No study cited here measures reading comprehension. Every figure is a reading rate.
- A book that declares no table of contents shows no chapter button. Both EPUB 2 and EPUB 3 require one, so this only affects malformed files, but the reader has no way to tell an absent list from an absent feature.
- The chapter panel does not scroll to the current chapter when it opens. The current chapter is highlighted, so a reader deep in a long book has to scroll to find where they are.
- A table of contents entry whose fragment names something the normalizer dropped lands at the start of its document rather than at the entry's own position.
- Chapter titles are shown exactly as the book writes them, including publisher noise and inconsistent casing.
- The reader chrome, the library controls and the note editor have been verified on Windows only. Nothing in any of them animates or translates a large area, which is the shape the Chrome throttle above actually reaches, but that is an expectation rather than a result. Sliding text *does* translate a large area, every frame, and it has not been measured on a phone either.
- Sliding text runs left to right only. Right-to-left scripts are shaped correctly within each word but the line still travels the same way, so a right-to-left book reads backwards on that surface. One word at a time is unaffected. Reading the ambient text direction was rejected rather than overlooked: it would mirror each word without mirroring the line, which is worse than being consistently wrong. See [ADR 0025](docs/adr/0025-continuous-scroll.md).
- A position saved while sliding lands on the word under the marker, not on the point inside it. Reading positions are stored per word, so resuming puts the marker at that word's leading edge — a shift of at most one word, and cheaper to accept than a schema change, a wire change and a server change to carry a fraction.
- The fade and fixation-letter settings, and the whole pacing model — steady, by length or manual, plus length scaling and the three pause lengths — do nothing under sliding text and are hidden while it is on. Speed is the one thing that carries over, and it is live there even on Manual, because the sliding line never waits for a press. Every hidden value is kept, so turning sliding off restores them.
- The eye-point caret takes your accent colour, and falls back to the surface ink wherever the accent cannot be told apart from the background you chose. Same rule as the reader's progress bar, and for the same reason: the two are picked on screens that know nothing about each other. It is the second accented thing on the reading surface, which is one more than the rest of the app allows itself.
- Turning sliding text off returns to the preset it was forked from, deleting the fork unless you changed the caret settings inside it, in which case it is kept and reused rather than duplicated the next time you turn it back on. The pairing is worked out from the profile's own settings, not stored, so a fork changed in any other way is treated as your own and left alone.
- Sliding text ignores a device asking apps to reduce motion, and says so in the profile editor rather than silently falling back. The motion here is the reading method rather than decoration, and a reader who selected it should not have it taken away without being told.

---

## Roadmap

1. Bookmarks and highlights over the same sync event log
2. Exporting and importing a profile as a file, so one can be shared with someone who does not share an account
3. Book transfer between devices, either over the local network or through the platform share sheet. Relaying files through the service is deliberately excluded: it would make this a system that transmits copyrighted content, which storing books on-device exists to avoid.
4. Public domain catalogue via OPDS feeds, with server-side ingestion
5. Google sign-in as an additional identity source
6. PDF support, which needs column detection, header and footer stripping, and reading-order reconstruction
7. A frame measurement of sliding text on a physical Android phone, and a pass with a screen reader over the sliding surface's step actions. Both are named as not-run in [ADR 0025](docs/adr/0025-continuous-scroll.md)
8. Right-to-left text on the sliding surface
9. An off-site copy of the nightly database dumps, which is what [ADR 0024](docs/adr/0024-database-backups.md) leaves open

---

## License

MIT. See [LICENSE](LICENSE).
