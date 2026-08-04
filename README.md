# Hereader

![dart](https://github.com/arnasbertulis/hereader/actions/workflows/ci-dart.yml/badge.svg?branch=main) ![flutter](https://github.com/arnasbertulis/hereader/actions/workflows/ci-flutter.yml/badge.svg?branch=main) ![java](https://github.com/arnasbertulis/hereader/actions/workflows/ci-java.yml/badge.svg?branch=main)

A configurable reading surface. Text is presented one word at a time in a fixed position, instead of as a page you scan with your eyes.

**Status: in active development.** Books can be imported and read, and a reading position follows the reader between devices. Not deployed yet, so the service has to be run locally. See [Current state](#current-state) for what works today.

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

**Two things the evidence says not to build.** Vertical text gave no benefit over horizontal RSVP for readers with left-of-scotoma retinal loci (Calabrèse et al., 2017). Increased line spacing does not improve reading speed in AMD patients, despite helping in normal peripheral vision (Chung et al., 2008).

### Not a medical device

This is an accessibility tool. It does not diagnose, treat, manage, or improve any condition, and no claim to that effect is made anywhere in this project. Anyone experiencing a change in their vision should see an ophthalmologist.

---

## Current state

**Working**

- [x] Tokenizer: whitespace splitting, attached punctuation, clause and sentence and paragraph pauses, abbreviation handling, numeric separators and units, line-break hyphen rejoining, Unicode-aware letter counting
- [x] Pacing models: constant, length-scaled, and reader-elicited advance
- [x] Reading profiles: pacing plus presentation settings, JSON round-tripping, forkable built-in presets
- [x] Playback state machine: play, pause, rewind-on-resume, reader-driven advance, seek by character offset
- [x] EPUB parsing: zip container, manifest and spine, HTML normalisation into blocks with stable ids
- [x] Front matter detection, so a book opens on its text rather than its licence page
- [x] Reading surface: word anchored per profile, punctuation gaps, keyboard control, reduce-motion support
- [x] Library: import, list, open, remove, and resume where you left off after a restart
- [x] Local persistence with drift, including an outbox for changes waiting to sync
- [x] Sync service: registration, login, token refresh, an append-only event log with per-user sequence numbers, idempotent pushes, hybrid logical clock ordering, and per-entity conflict resolution
- [x] Sync client: hybrid logical clocks in Dart, tokens in the platform keystore, transparent token refresh, an outbox drainer, and sign-in that is offered rather than required
- [x] A sheet asking the reader which position they meant when two devices diverge
- [x] Test suite across all of the above, including a real Project Gutenberg book as a golden fixture, effective words per minute over real prose, virtual-clock playback timing, sync ordering and divergence against a real Postgres, and the sync client against a fake service
- [x] CI running analyzer and tests on every push, across every package, the app, and the service

**Not started**

- [ ] Deployment: the service runs locally only
- [ ] Settings screen, so profiles can be edited rather than only chosen
- [ ] Chapter navigation

---

## How sync works

The reader's device is authoritative for reading. Everything works with no network, because a reading app that stalls on a dead connection is a broken reading app. An account is offered and never required.

Writes go to the local database and append an event to an outbox, in one transaction: a position that reached disk without an outbox entry would never sync, and an entry without a position would sync a change the device does not have. A sender drains the outbox when there is a connection. The service assigns each accepted event a sequence number that is monotonic per user, and other devices pull everything after the number they last saw.

**Ordering uses hybrid logical clocks.** Wall clocks disagree across devices, so ordering by timestamp can pick the older write. A pure counter orders correctly but loses any relation to real time. An HLC is a millisecond, a counter for writes in the same millisecond, and a device id to break ties. It sorts as a string and never moves backwards, even if the system clock does.

Clients supply their own stamps, so the service does not trust them. A stamp more than five minutes ahead of server time is rejected rather than clamped: rewriting it would break the client's own local ordering, and a device claiming next week would otherwise win every comparison from then on.

**Retries are safe.** Every event carries a client-generated idempotency key, enforced by a unique constraint rather than a check followed by an insert, so a push resent after a lost response cannot apply twice under concurrency. An event the service refuses outright counts against a limit and is eventually parked, so one bad event cannot block everything queued behind it.

**Conflict resolution differs by entity, which is the substantive decision.** Preferences and profiles take last write wins, because a stale font size costs nothing. Deletions leave tombstones, because a row that vanished entirely would be resurrected by any device that was offline when it happened. Reading positions are different: being dropped in the wrong chapter is the failure a reader actually notices. Two devices within 500 tokens of each other resolve silently; beyond that, the divergence is recorded and the reader is asked which position they meant.

One device moving a long way is not a divergence — that is an afternoon of reading. It takes two devices disagreeing.

Recorded in [`docs/adr/0005-sync-event-log.md`](docs/adr/0005-sync-event-log.md).

---

## Design decisions worth knowing

**Reading positions are character offsets, never word indices.** A word index shifts the moment the tokenizer changes, which would silently move every saved position in every book. Character offsets into the source block survive tokenizer changes, and locators carry a `parserVersion` so future changes can be migrated deliberately. Recorded in [`docs/adr/0002-locator-format.md`](docs/adr/0002-locator-format.md).

**Pacing returns a decision, not a duration.** Reader-elicited advance has no duration; the word waits for input that may never arrive. Encoding that as a zero or sentinel `Duration` would make one value mean two things, so `decide` returns a sealed type with `Hold` and `AwaitAdvance` variants. Recorded in [`docs/adr/0003-pacing-decision-model.md`](docs/adr/0003-pacing-decision-model.md).

**Book files are stored; parsed text is not.** Parsed output is derived data, and a parser change invalidates every cached copy. Keeping the source file means the parser stays the single source of truth and a normalisation improvement applies to books already in the library. Recorded in [`docs/adr/0004-store-book-files.md`](docs/adr/0004-store-book-files.md).

**The service issues its own tokens.** Not delegating to Firebase or Google as the token issuer means a social login can be added later purely as an identity source, without reworking how the API authenticates. Access and refresh tokens carry a type claim; without it a refresh token would work as an access token and quietly extend every session to the refresh window.

**Tokens live in the platform keystore, not the app database.** A refresh token is a two-month credential: anyone who reads it can act as the reader until it expires. The database holds book files and reading positions, which are private but are not credentials, and it is readable by anything with the device's filesystem. On the web there is no keystore, which is one reason to treat that target as the least trusted.

**The divergence hint is used by the service and ignored by the reader.** A position carries a token index so the service can judge how far apart two devices are without holding a copy of the book. It cannot verify that number. The service uses it for a threshold, where a wrong value costs a prompt that was not needed or misses one that was. The app does not show it: both candidates are resolved against this device's own copy, because a sheet promising 30% through and then landing the reader at 4% is worse than no sheet at all.

**Front matter is skipped, never removed.** Dropping blocks would shift every block id and invalidate saved positions, and a wrong guess would delete real text with no way back. Detection only reports a suggested opening index, so the reader can rewind into the licence page if they want it.

**Waiting for the reader is not the same as being paused.** Under reader-elicited pacing the session sits in `awaitingAdvance`, a distinct state from `paused`. Collapsing the two would make the pause button meaningless in that mode and would fire the profile's rewind on every single word.

**Profiles are plain data, including their colours.** Presentation settings live in the pure Dart engine rather than the Flutter app, so they serialise, round-trip and test without a widget harness. The cost is that colours are stored as ARGB integers and the app maps them at the boundary.

**Punctuation stays attached to its word.** Flashing a lone comma on screen makes no sense. It also means the tokenizer only inspects the *end* of a token, so interior periods and commas stop being a special case. `1,234.56`, `don't`, and `e.g.` all fall out of one rule rather than three.

**Units stay attached to their number.** `2005 m.` and `11 d.` appear as one token rather than a number followed by a bare unit, which would be meaningless on screen and would read the period as a sentence end. Suffix sets are per-language rather than hardcoded.

**Hyphenation is resolved during the walk, not by preprocessing.** Rewriting the source string to strip `-\n` would invalidate every character offset computed afterward.

**The reading engine has no Flutter dependency.** `rsvp_engine` and `epub_reader` are plain Dart, so the entire core is testable in about a second without a widget harness. Playback timing is tested against a virtual clock, so a five-minute reading session runs in microseconds.

**Books imported by the reader never leave the device.** Parsing happens on-device. The service stores reading positions, preferences, and metadata only. This is a deliberate privacy and licensing decision, and it is why a book has to be imported on each device that reads it.

---

## Repository layout

```
packages/rsvp_engine/     Pure Dart. Tokenizer, pacing models, reading
                          profiles, playback state machine, locators,
                          hybrid logical clocks.
packages/epub_reader/     Pure Dart. Zip container and OPF parsing, HTML
                          normalisation, front matter detection.
app/                      Flutter client. Android, Windows, web.
server/                   Spring Boot service. Auth, sync event log,
                          conflict resolution. Postgres via Flyway.
docs/adr/                 Architecture decision records.
docs/research/            Evidence notes behind the design.
```

---

## Running it

### The sync service

Optional: the app reads perfectly well without it, and only needs it to sync
between devices.

Requires JDK 25 and a Postgres. The Maven wrapper handles the rest.

```bash
docker run --name hereader-db -e POSTGRES_PASSWORD=dev \
  -e POSTGRES_DB=hereader -p 5432:5432 -d postgres:17
```

The service refuses to start without a signing secret, deliberately: a
placeholder that ships in a repository is worse than a service that is down.

```bash
cd server
export JWT_SECRET=$(head -c 48 /dev/urandom | base64)   # any 32+ byte string
./mvnw spring-boot:run
```

Flyway applies the schema on first start. `GET /health` reports whether the
service can reach its database, not merely whether the process is alive.

```bash
./mvnw verify   # tests need a hereader_test database
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

Add an EPUB from the library screen and read it. Books and reading positions
persist across restarts. There is also a paste screen for reading arbitrary
text without a file.

The app expects the service on `http://localhost:8080`. Point it elsewhere at
build time:

```bash
flutter run --dart-define=HEREADER_API=https://api.example.com
```

---

## Known limitations

- Not deployed. The service runs locally, so syncing between two devices means both reaching the same machine.
- Books do not transfer between devices. Reading positions sync, but the file itself has to be imported on each device.
- Opening a book waits on a sync attempt so the reader never starts from a position that is about to change. A slow connection therefore delays opening, bounded by a fifteen second request timeout.
- A rejected batch counts the attempt against every event in it, not just the one the service objected to. Coarse, but the alternative is pushing events one at a time.
- Position divergence is judged from a token index the client supplies. The service cannot verify it, and a wrong value causes a prompt that was not needed or misses one that was. The locator itself remains authoritative, and the app resolves both candidates locally rather than trusting the hint.
- Duplicate events consume a sequence number that is then skipped, so the log has gaps and `lastSeq` overstates how many events exist. Harmless, since clients ask for everything after a number rather than counting.
- The event log grows without bound. Compaction is not implemented and is not needed at the scale this will see.
- Profiles arrive from other devices but are not applied, because editing them needs a settings screen that does not exist yet.
- Every book open re-parses the file, which takes a few hundred milliseconds for a novel. Caching parsed blocks keyed by parser version is the fix if this becomes a problem.
- Book bytes live in a database column. Fine for text, less comfortable for a heavily illustrated volume of tens of megabytes.
- A reading position is saved when the reader closes a book, not periodically. Killing the app mid-chapter loses the place.
- Front matter detection uses an explicit marker where a book provides one, and pattern matching otherwise. The pattern path is a guess, capped at fifteen percent of a book and never destructive, but it can still skip a dedication that looks like a rights line.
- Tables, images, figures and MathML are dropped rather than flattened. Reading a table cell one word at a time loses what made it a table.
- The tokenizer reads `Chapter 3.` as a sentence end. Telling list numbering apart from sentence terminators needs context the current design does not carry.
- The abbreviation list is English-only, while the numeric suffix list defaults to Lithuanian and metric units. Both are constructor parameters on `Tokenizer`, so a per-language set can be supplied, but nothing selects one automatically yet.
- A date that genuinely ends a sentence, such as `įvyko 2005 m.`, loses its sentence pause, because the unit is treated as an abbreviation rather than a terminator. Same ambiguity as `e.g.`, and unsolvable without more context than the tokenizer carries.
- Length-scaled pacing normalises against a fixed reference word length, so the configured words-per-minute is only accurate on average. Text whose mean word length differs sharply from English will read faster or slower than the setting says.
- Chunk sizes above one token are rejected. Showing several words per advance requires pacing to decide over a group rather than a token, which the engine does not do yet.
- Pausing mid-word restarts that word's full duration on resume rather than preserving the remainder. The difference is a few hundred milliseconds and was not judged worth the bookkeeping.
- The optimal recognition point highlight is offered as a preference with no evidence behind it. None of the studies above tested it.
- iOS is untested. The codebase targets it, but building and signing requires macOS hardware.
- Flutter web renders text to canvas rather than DOM, so screen reader support on the web target is weaker than a conventional website. There is also no keystore there, so tokens fall back to local storage.
- The supporting research is small-sample and predates modern displays. Rubin and Turano tested 23 people in 1994; Arditi tested 15 in 1999. These are the best available comparisons, not large trials.
- No study cited here measures reading comprehension. Every figure is a reading rate.

---

## Roadmap

1. Deployment to a public URL, with the service containerised and deployed on merge
2. Settings screen, so profiles can be edited rather than only chosen
3. Chapter navigation from the book's own table of contents
4. Bookmarks and highlights over the same sync event log
5. Book transfer between devices, either over the local network or through the platform share sheet. Relaying files through the service is deliberately excluded: it would make this a system that transmits copyrighted content, which storing books on-device exists to avoid.
6. Public domain catalogue via OPDS feeds, with server-side ingestion
7. Google sign-in as an additional identity source
8. PDF support, which needs column detection, header and footer stripping, and reading-order reconstruction
9. Continuous scrolling presentation, as a separate renderer rather than a toggle. Smooth scroll needs constant velocity, so honouring a per-token duration would make text surge and stall mid-sentence. Whether per-token pacing collapses into a single velocity, or that mode drops pacing entirely, is unresolved.

---

## License

MIT. See [LICENSE](LICENSE).
