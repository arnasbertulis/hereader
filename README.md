# Hereader

![dart](https://github.com/arnasbertulis/hereader/actions/workflows/ci-dart.yml/badge.svg?branch=main) ![flutter](https://github.com/arnasbertulis/hereader/actions/workflows/ci-flutter.yml/badge.svg?branch=main)

A configurable reading surface. Text is presented one word at a time in a fixed position, instead of as a page you scan with your eyes.

**Status: in active development.** The reading engine is complete and tested, and pasted text can be read in the app. There is no way to open a book yet. See [Current state](#current-state) for what works today.

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

- [x] Monorepo scaffold: two pure Dart packages plus the Flutter app
- [x] `Token` model with source character offsets and pause classification
- [x] Tokenizer: whitespace splitting, attached punctuation, clause and sentence and paragraph pauses, abbreviation handling, numeric separators, line-break hyphen rejoining, Unicode-aware letter counting
- [x] Pacing models: constant, length-scaled, and reader-elicited advance
- [x] Reading profiles: pacing plus presentation settings, JSON round-tripping, forkable built-in presets
- [x] Playback state machine: play, pause, rewind-on-resume, reader-driven advance, seek by character offset
- [x] Test suite covering all of the above, including effective words per minute over real prose and virtual-clock playback timing
- [x] CI running analyzer and tests on every push
- [x] Reading surface: word anchored per profile, punctuation gaps, keyboard control, reduce-motion support
- [x] Paste-to-read screen with preset selection

**Not started**

- [ ] EPUB parsing and normalisation
- [ ] Library screen, settings, and reading from a file
- [ ] Local persistence
- [ ] Backend: auth, sync event log, conflict resolution
- [ ] Deployment

---

## Design decisions worth knowing

**Reading positions are character offsets, never word indices.** A word index shifts the moment the tokenizer changes, which would silently move every saved position in every book. Character offsets into the source block survive tokenizer changes, and locators carry a `parserVersion` so future changes can be migrated deliberately. Recorded in [`docs/adr/0002-locator-format.md`](docs/adr/0002-locator-format.md).

**Pacing returns a decision, not a duration.** Reader-elicited advance has no duration; the word waits for input that may never arrive. Encoding that as a zero or sentinel `Duration` would make one value mean two things, so `decide` returns a sealed type with `Hold` and `AwaitAdvance` variants. Recorded in [`docs/adr/0003-pacing-decision-model.md`](docs/adr/0003-pacing-decision-model.md).

**Waiting for the reader is not the same as being paused.** Under reader-elicited pacing the session sits in `awaitingAdvance`, a distinct state from `paused`. Collapsing the two would make the pause button meaningless in that mode and would fire the profile's rewind on every single word.

**Profiles are plain data, including their colours.** Presentation settings live in the pure Dart engine rather than the Flutter app, so they serialise, round-trip and test without a widget harness. The cost is that colours are stored as ARGB integers and the app maps them at the boundary. Profiles cross the sync boundary later, which is what makes this worth the small ugliness.

**Punctuation stays attached to its word.** Flashing a lone comma on screen makes no sense. It also means the tokenizer only inspects the *end* of a token, so interior periods and commas stop being a special case. `1,234.56`, `don't`, and `e.g.` all fall out of one rule rather than three.

**Units stay attached to their number.** `2005 m.` and `11 d.` appear as one token rather than a number followed by a bare unit, which would be meaningless on screen and would read the period as a sentence end. Suffix sets are per-language rather than hardcoded.

**Hyphenation is resolved during the walk, not by preprocessing.** Rewriting the source string to strip `-\n` would invalidate every character offset computed afterward.

**The reading engine has no Flutter dependency.** `rsvp_engine` and `epub_reader` are plain Dart, so the entire core is testable in under a second without a widget harness. Playback timing is tested against a virtual clock, so a five-minute reading session runs in microseconds.

**Books imported by the user never leave the device.** Parsing happens on-device. The server stores reading positions, preferences, and metadata only. This is a deliberate privacy and licensing decision.

---

## Repository layout

```
packages/rsvp_engine/     Pure Dart. Tokenizer, pacing models,
                          reading profiles, playback state machine.
packages/epub_reader/     Pure Dart. EPUB container parsing.    (not started)
app/                      Flutter client. Android, Windows, web.
server/                   API service. Auth, sync event log.    (not started)
docs/adr/                 Architecture decision records.
docs/research/            Evidence notes behind the design.
```

---

## Running it

Requires the Flutter SDK, which bundles Dart.

```bash
git clone https://github.com/arnasbertulis/hereader.git
cd hereader/packages/rsvp_engine
dart test
dart analyze
```

The app currently opens on a paste screen: drop in any text, choose a profile, and read it. Book import comes next.

```bash
cd app
flutter run -d windows   # or -d chrome
```

---

## Known limitations

- The tokenizer reads `Chapter 3.` as a sentence end. Telling list numbering apart from sentence terminators needs context the current design does not carry.
- The abbreviation list is English-only, while the numeric suffix list defaults to Lithuanian and metric units. Both are constructor parameters on `Tokenizer`, so a per-language set can be supplied, but nothing selects one automatically yet.
- A date that genuinely ends a sentence, such as `įvyko 2005 m.`, loses its sentence pause, because the unit is treated as an abbreviation rather than a terminator. Same ambiguity as `e.g.`, and unsolvable without more context than the tokenizer carries.
- No handling yet for sentence boundaries that are ambiguous across quotation marks.
- Length-scaled pacing normalises against a fixed reference word length, so the configured words-per-minute is only accurate on average. Text whose mean word length differs sharply from English will read faster or slower than the setting says.
- Chunk sizes above one token are rejected. Showing several words per advance requires pacing to decide over a group rather than a token, which the engine does not do yet.
- Pausing mid-word restarts that word's full duration on resume rather than preserving the remainder. The difference is a few hundred milliseconds and was not judged worth the bookkeeping.
- The optimal recognition point highlight is offered as a preference with no evidence behind it. None of the studies above tested it.
- iOS is untested. The codebase targets it, but building and signing requires macOS hardware.
- Flutter web renders text to canvas rather than DOM, so screen reader support on the web target is weaker than a conventional website.
- The supporting research is small-sample and predates modern displays. Rubin and Turano tested 23 people in 1994; Arditi tested 15 in 1999. These are the best available comparisons, not large trials.
- No study cited here measures reading comprehension. Every figure is a reading rate.

---

## Roadmap

1. EPUB import, block normalisation, and the reader surface
2. Local library and progress persistence
3. Backend auth and offline-first sync with conflict resolution
4. Bookmarks and highlights over the same sync event log
5. Public domain catalogue via OPDS feeds, with server-side ingestion
6. Google sign-in as an additional identity source
7. PDF support, which needs column detection, header and footer stripping, and reading-order reconstruction
8. Continuous scrolling presentation, as a separate renderer rather than a toggle. Smooth scroll needs constant velocity, so honouring a per-token duration would make text surge and stall mid-sentence. Whether per-token pacing collapses into a single velocity, or that mode drops pacing entirely, is unresolved.

---

## License

MIT. See [LICENSE](LICENSE).
