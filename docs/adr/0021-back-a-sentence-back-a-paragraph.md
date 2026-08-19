# 21. Back a sentence, back a paragraph

Date: 2026-08-19

## Status

Accepted. Un-rejects ADR 0020's "two rows of controls" alternative.

## Context

ADR 0020 gave the reader two forward jumps and left backward movement as the
left tap zone stepping by `ui.step_words` — one to ten words, device-local.
That is a fine way to undo an overshoot by a word or two. It is not a way to
re-read the sentence a reader is already in, which is the more common need: a
word missed at a fixed anchor cannot be found again by looking, the way it can
on a page, and stepping back by an arbitrary word count means counting rather
than reading.

`_text()`, the fixture every existing test on the reader screen used, never put
more than one sentence in a block, so nothing exercised a jump from *inside* a
multi-sentence block — every landing tested there was also a block boundary.
Adding the backward pair was the occasion to close that gap in the forward
pair's coverage too, in `reader_tap_zones_test.dart`.

## Decision

### 1. Two backward jumps, restarting the unit before leaving it

`TokenizedText.previousSentenceStart` and `previousParagraphStart` mirror the
forward pair's contract — null rather than a clamp, so the button disables
instead of moving nowhere — but answer a different question: not "the unit
before this token" but "the start of the unit this token is in, unless it is
already there, in which case the unit before."

This is the "previous track" rule a media player applies to skip-back, chosen
over always moving to the previous unit because re-reading the sentence just
missed is the need a low-vision reader has most often, and a control that can
only ever leave the current unit cannot offer that at all — it would take a
forward jump and a backward jump together to land back where a reader already
was.

Both apply the masking rule their forward counterparts document: a sentence
boundary is a token whose `pauseAfter` is `sentence` *or* `paragraph`, because
a full stop before a blank line reports only the longer pause. A backward scan
that matched `sentence` alone would walk straight past a boundary the forward
scan already knows to catch.

### 2. Three rows: progress, then four jumps, then close · play · profile

The reading surface's controls are now a nav row of four — back a paragraph,
back a sentence, forward a sentence, forward a paragraph, outward from a
centre that is not itself a button — above a second row of close, play and
profile. Play moves down into that second row and stays the largest glyph at
44dp, now the middle of three rather than the middle of five.

This un-rejects ADR 0020's "two rows of controls" alternative, which was
rejected there for costing vertical space over a background the reader chose.
The trade changed with the count: two rows for five controls bought nothing a
`spaceEvenly` single row didn't already give for free, but two rows for six —
four jumps plus three book-level controls — separate two different questions
("where in this sentence" against "what to do with this book") onto two lines
instead of interleaving them, and a single row of seven no longer fits: seven
48dp targets need 336dp of width, past the 320dp viewport floor this app is
built against, and play stops being the row's centre so `spaceEvenly` no
longer centres it.

### 3. Two more icons, verified the same way as the last two

`AppIcons.backSentence` and `AppIcons.backParagraph` are Phosphor's
`skip-back` (`0xe5a4`) and `rewind` (`0xe6a8`) at Light, the mirror pair of
`skip-forward` and `fast-forward` already in use. Found in the cached
`phosphor_flutter` source rather than guessed, then — per ADR 0020's own
verification step — checked against the `cmap` of the vendored
`Phosphor-Light.ttf` directly rather than trusted from the package alone: both
codepoints resolve to glyphs, and to the adjacent glyph ids of their forward
counterparts (733 beside 734, 863 beside 862), which is what a genuine mirror
pair in one font looks like.

### 4. Modifier keys, not new keys

`Ctrl`+`Left`/`Right` reach a sentence, `Shift`+`Left`/`Right` reach a
paragraph, in both directions, alongside the bare arrows that still step by
`ui.step_words`. Modifiers rather than new letters because the pairing already
exists on the buttons — sentence is the shorter jump, paragraph the longer —
and a modifier reuses the direction the bare arrow already carries rather than
asking the reader to learn two new keys per direction. Each binding calls
through the same `_jumpTo` the buttons use, so a key at the end of the book is
a no-op rather than something a disabled button would refuse and a key would
not.

## Consequences

**The two back buttons now sit over the lower part of the left tap zone.**
That strip jumps by a sentence or a paragraph instead of stepping by
`ui.step_words`, the same trade the two forward buttons already made on the
right in ADR 0020. Recorded rather than treated as new: the zone fills the
whole surface and the chrome above it was always going to claim whatever sits
under the buttons it draws.

**Chapter navigation's resume-rewind fault is unchanged and still open.**
`_goToChapter` and `_goToFrontMatter` use `seekToIndex`, not `stopAt`, and nothing
here touches them. ADR 0020 recorded this; this ADR does not close it.

## Alternatives rejected

**Always move to the previous sentence or paragraph, mid-unit or not.** Fewer
presses to move back a long way, and the simpler rule to state. Rejected: it
removes the one motion — restart what I'm on — a low-vision reader reaches for
most, in favour of a motion that is already available by pressing the same
button twice from a unit's own start.

**One row of seven controls.** Zero new vertical space. Rejected on the
arithmetic in section 2: it does not fit a 320dp viewport, and play is no
longer the row's centre.

**Larger glyphs for the two back buttons alone.** Would read as the newer,
attention-getting variant. Rejected: the row is meant to read as one family of
four equal jumps around a centre, and asymmetric sizing would undercut that
before hierarchy is even a question here — hierarchy on this screen is still
play against everything else, unchanged.

## Verification

`dart test` and `dart test -p chrome` in `packages/rsvp_engine`: 226 tests
green on both targets, 15 new for `previousSentenceStart` and
`previousParagraphStart` in `tokenized_text_test.dart`, mirroring the forward
pair's fixture and masking cases plus the two negative/out-of-range contracts
those methods keep asymmetric on purpose.

`flutter test` in `app/`: 980 tests green, including a multi-sentence-block
group for the forward jumps in `reader_tap_zones_test.dart` (closing the
coverage gap described in Context), a new "the backward jumps" group, a new
"the four jumps by keyboard" group, two more cases under "resuming after a
step", and a tooltip-coverage group in `reader_semantics_test.dart`.

`flutter analyze` clean, `flutter build web` succeeded.

**A manual pass in Chrome**, using its device emulation for the mobile case,
against the web build. The three-row layout and all four jumps were exercised
by hand: landing correctly from mid-unit and from a unit's own start, and
greying out at the start and end of the book.

**Still not run: the modifier keys on a real keyboard, and anything on a
physical device.** The emulated pass answers the layout and touch-target
questions; it does not exercise `Ctrl`/`Shift` bindings, which want a physical
keyboard, and it does not answer ADR 0019's still-open question of whether the
Light weight holds up at 20-24dp against real pixels. Both gaps stand
alongside the ones ADR 0020 already recorded.
