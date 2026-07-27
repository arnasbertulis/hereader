# Hereader

A configurable reading surface. Text is presented one word at a time in a fixed position, instead of as a page you scan with your eyes.

**Status: in active development.** The reading engine is partially built. Nothing is usable end to end yet. See [Current state](#current-state) for what works today.

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

**Two things the evidence says not to build.** Vertical text gave no benefit over horizontal RSVP for readers with left-of-scotoma retinal loci (Calabrèse et al., 2017). Increased line spacing does not improve reading speed in AMD patients, despite helping in normal peripheral vision (Chung et al., 2008).

### Not a medical device

This is an accessibility tool. It does not diagnose, treat, manage, or improve any condition, and no claim to that effect is made anywhere in this project. Anyone experiencing a change in their vision should see an ophthalmologist.

---

## Current state

**Working**

- [x] Monorepo scaffold: two pure Dart packages plus the Flutter app
- [x] `Token` model with source character offsets and pause classification
- [x] Tokenizer: whitespace splitting, attached punctuation, clause and sentence and paragraph pauses, abbreviation handling, numeric separators, soft-hyphen line rejoining, Unicode-aware letter counting
- [x] Unit test suite covering the above
- [x] CI running analyzer and tests on every push

**Not started**

- [ ] Pacing models: constant, length-scaled, reader-elicited
- [ ] Presentation profiles and presets
- [ ] Playback state machine with rewind-on-pause
- [ ] EPUB parsing and normalisation
- [ ] Reader and library UI
- [ ] Local persistence
- [ ] Backend: auth, sync event log, conflict resolution
- [ ] Deployment

---

## Design decisions worth knowing

**Reading positions are character offsets, never word indices.** A word index shifts the moment the tokenizer changes, which would silently move every saved position in every book. Character offsets into the source block survive tokenizer changes, and locators carry a `parserVersion` so future changes can be migrated deliberately. Recorded in [`docs/adr/0002-locator-format.md`](docs/adr/0002-locator-format.md).

**Punctuation stays attached to its word.** Flashing a lone comma on screen makes no sense. It also means the tokenizer only inspects the *end* of a token, so interior periods and commas stop being a special case. `1,234.56`, `don't`, and `e.g.` all fall out of one rule rather than three.

**Hyphenation is resolved during the walk, not by preprocessing.** Rewriting the source string to strip `-\n` would invalidate every character offset computed afterward.

**The reading engine has no Flutter dependency.** `rsvp_engine` and `epub_reader` are plain Dart, so the entire core is testable in under a second without a widget harness.

**Books imported by the user never leave the device.** Parsing happens on-device. The server stores reading positions, preferences, and metadata only. This is a deliberate privacy and licensing decision.

---

## Repository layout

```
packages/rsvp_engine/     Pure Dart. Tokenizer, pacing, locators, playback.
packages/epub_reader/     Pure Dart. EPUB container parsing and normalisation.
app/                      Flutter client. Android, Windows, web.
server/                   API service. Auth, sync event log.       (not started)
docs/adr/                 Architecture decision records.
docs/research/            Evidence notes behind the design.
```

---

## Running it

Requires the Flutter SDK, which bundles Dart.

```bash
git clone https://github.com/arnasbertulis/hereader.git
cd hereader/packages/rsvp_engine
dart pub get
dart test
dart analyze
```

The Flutter app builds and launches but contains no project code yet.

```bash
cd app
flutter run -d windows   # or -d chrome
```

---

## Known limitations

- The tokenizer reads `Chapter 3.` as a sentence end. Telling list numbering apart from sentence terminators needs context the current design does not carry.
- The abbreviation list is English-only. Lithuanian and other languages need their own; `Tokenizer` takes the set as a constructor parameter for this reason.
- No handling yet for sentence boundaries that are ambiguous across quotation marks.
- iOS is untested. The codebase targets it, but building and signing requires macOS hardware.
- Flutter web renders text to canvas rather than DOM, so screen reader support on the web target is weaker than a conventional website.
- The supporting research is small-sample and predates modern displays. Rubin and Turano tested 23 people in 1994; Arditi tested 15 in 1999. These are the best available comparisons, not large trials.
- No study cited here measures reading comprehension. Every figure is a reading rate.

---

## Roadmap

1. Pacing models and presentation profiles, including reader-elicited advance
2. EPUB import and the reader surface
3. Local library and progress persistence
4. Backend auth and offline-first sync with conflict resolution
5. Bookmarks and highlights over the same sync event log
6. Public domain catalogue via OPDS feeds, with server-side ingestion
7. Google sign-in as an additional identity source
8. PDF support, which needs column detection, header and footer stripping, and reading-order reconstruction

---

## License

MIT. See [LICENSE](LICENSE).
