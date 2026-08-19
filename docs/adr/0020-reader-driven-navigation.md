# 20. Reader-driven navigation: tap zones, a step of the reader's own, and two forward jumps

Date: 2026-08-18

## Status

Accepted. Completes the tap zones ADR 0015 deferred.

**Section 5's row order and the "two rows of controls" rejection in
Alternatives are superseded by
[ADR 0021](0021-back-a-sentence-back-a-paragraph.md)**, which adds a backward
sentence and paragraph jump and moves to a three-row layout: a nav row of four
jumps above a row of close, play and profile. Everything else here —
the three tap zones, `stopAt`, `ui.step_words`, and the jump semantics in
section 4 — stands unchanged.

**The Consequences entry recording chapter navigation's resume-rewind fault as
open is closed by
[ADR 0022](0022-chapter-jumps-also-suppress-the-resume-rewind.md)**, which
moves `_goToChapter` and `_goToFrontMatter` onto `stopAt`.

## Context

ADR 0015 removed the rewind button from the reading surface and moved rewind
onto `arrowLeft`, saying: "Tap zones on the left and right of the surface
replace the button, and are not in this change." `app/README.md` recorded the
consequence — "a keyboard, a switch, or a screen reader is the only way back
until then" — which on Android, the target this app is aimed at, means no way
back at all. A reader who overshoots a sentence has to close the book.

Forward was no better. `arrowRight` called `PlaybackSession.advance()`, which
moves exactly one token and has no count parameter, while `arrowLeft` called
`rewind(_profile.rewindWords)`, which moves two by default. The settings page
described both as "one word". Neither key stopped the stream, so a reader
stepping while playing watched their step scroll away.

And there was nothing between one word and one chapter. The chapter drawer is
the only other jump on this screen, and a reader who wants to skip a
description does not want to skip to Act III.

## Decision

### 1. The surface is three regions, split 25 / 50 / 25

The left and right quarters step back and forward and stop there. The centre
half keeps every job the whole surface had: play, pause, and the advance under
elicited pacing.

A generous centre because that tap is the primary control of the app and a
mis-hit costs the reader their place in a sentence, while a mis-hit on an edge
costs them one step they can undo with the zone opposite.

The split is `Row` of `Expanded` with flex 1/2/1 inside a `Positioned.fill`,
not arithmetic over a measured width. That puts the geometry in the layout,
which is also where a screen reader reads each button's bounds from, so the
split is written down once.

The zone row sits *before* the controls in the `Stack`, so the close, profile,
play, chapter and jump buttons stay above it and keep their own taps. The
single `GestureDetector` this replaces wrapped all of them.

### 2. A step is a place the reader chose, and resuming does not undo it

`PlaybackSession.stopAt(int)` is new: it moves, stops, and suppresses exactly
one resume rewind. Every reader-driven step goes through it — both zones, both
jump buttons, both arrow keys.

Without the suppression, `play()` would apply `ReadingProfile.rewindWords` on
the way out of the `paused` state a step just produced. Under a tap zone the
step and the resume land one after the other on every single press, so a
reader stepping forward one word and pressing play would end up two words
*behind* where they started.

`rewindWords` is not wrong; it is answering a different question. It exists so
a reader coming back to a book re-enters the sentence with some context. A
reader who has just stepped onto a particular word has no context to recover —
they are looking at the word they picked.

The suppression lasts one `play()` and any `pause()` clears it, so it describes
the last thing the reader did rather than accumulating.

`awaitingAdvance` is the one state `stopAt` does not turn into a pause. Under
elicited pacing that state is active reading, one press at a time — the enum's
own doc says so — and dropping the reader into `paused` on every step would
make them find the play button to get their advance back.

### 3. The step amount is a device-local preference, not a profile field

`ui.step_words` on Settings › Reading, default 1, range 1–10, alongside
`ui.time_left_scope` and written with `sync: false` like every other `ui.` key.

This is the decision most at risk of looking like the mistake ADR 0015 warned
about: "two numbers for one idea is how they drift." The two numbers are
`stepWords` and `rewindWords`, and what keeps them apart is that they are not
one idea.

- `rewindWords` is how far a **resume** re-enters context. That belongs to a
  reading style — `Presets.slowLowVision` sets 3 where standard sets 2 — so it
  travels with the profile and syncs.
- `stepWords` is how far one **deliberate step** moves. That belongs to the
  input. A thumb on a phone reaching a quarter of the screen and an arrow key
  on a desktop want different grains, and the same reader using both wants two
  different answers on the two devices. So it stays on the device.

The test for whether they have drifted is whether changing one should change
the other, and it should not: a reader who lengthens their resume rewind has
said nothing about how far a tap moves.

Minimum of one rather than zero. At zero both edges become controls that
visibly do nothing, and the centre already covers stopping where you are.
`decodeStepWords` clamps rather than falling back, because a value from a
build offering a wider range still says which end the reader wanted.

`ReaderScreen` reads the key itself at open through the repository it already
holds, decoded by the same `decodeStepWords`, rather than taking a
`ReadingDisplayController`. Home and Library listen to one because they stay
alive in the shell's cross-fading stack while Settings changes underneath them;
the reader is a route pushed above the shell and torn down on exit, so the
value cannot go stale while a book is open. Threading a controller through
`BookOpener` is also what ADR 0015 rejected for `AppearanceController`, for the
same shape of reason.

### 4. Two forward jumps, in the control row

**A sentence** is `TokenizedText.nextSentenceStart`, the first token after one
whose `pauseAfter` is `sentence` *or* `paragraph`. Accepting `paragraph` is not
sloppiness: `Tokenizer` takes the longer of the pause its punctuation implies
and the pause its trailing whitespace implies, so a `.` followed by a blank
line reports `paragraph` and the sentence end underneath it is invisible.
Matching `sentence` alone would step clean over it.

A block-final `.` is *not* that case and reports `sentence`, because blocks are
tokenized one at a time and nothing follows the last token of one for the
whitespace rule to read. The first version of this ADR had that backwards; the
test written from it failed and the reasoning was corrected rather than the
assertion.

**A paragraph** is `TokenizedText.nextParagraphStart`, the nearer of the next
block start and the next in-block `PauseAfter.paragraph`. Both sources are
needed for different texts: `HtmlNormalizer` emits one block per `<p>`, so for
an EPUB and for a note the block boundary is the paragraph boundary and the
second source never fires — but this type takes blocks from any caller, and
prose that never went through a normalizer carries its paragraphs as blank
lines inside one block.

Both return null at the end rather than clamping, so the buttons disable rather
than offering a jump that moves nowhere.

### 5. The row is close · profile · play · sentence · paragraph

Both jumps move forward, so both sit to the right of play, where forward reads
as forward. Keeping close and profile on the outside would have put the shorter
jump on play's left, where the eye reads it as going back — and back is the one
thing in this row that is not a glyph at all.

Play stays the middle of five equal-width secondaries, so `spaceEvenly` still
centres it exactly. Hierarchy is still size: 44 against 28.

Rewind is still not a button. Adding a glyph for the one action that now has a
zone of its own would give it two homes.

The disabled glyph is the same ink at Material's own disabled opacity. ADR
0015's one ink is not broken by an opacity, and nothing else on this screen
could carry "unavailable".

### 6. The arrow keys are the zones

`arrowLeft` and `arrowRight` both step by `stepWords` and stop, so the reader
with a keyboard and the reader with a thumb are doing one thing rather than two
that drift. The settings page's shortcut list, which said "Back one word" while
the key stepped two, now says "Back a step" and "Forward a step".

## Consequences

**Chapter navigation has the same fault and is not fixed here.** Jumping to a
chapter while paused and then pressing play still steps back by `rewindWords`,
landing the reader in the previous chapter's last words. `_goToChapter` and
`_goToFrontMatter` use `seekToIndex`, which is left untouched because it keeps
playing when it was playing and that is what chapter navigation wants. Moving
them onto `stopAt` would change two behaviours at once. Recorded as a gap.

**The reading surface's semantics are three nodes, not one.** Each zone is a
button with its own label; the edges name the configured number, which a screen
reader user cannot see from the settings page. `RsvpView` is under an
`ExcludeSemantics` and announces nothing of its own — the word moved onto the
centre zone's `value`, which is where the control that stops on it lives.

That costs one extra leaf rebuild per word: the centre zone's `Semantics` sits
in its own `ValueListenableBuilder` so the word stays current, while the edges
do not. No layout and no chrome rebuilds, which is what ADR 0013's notifier was
protecting.

**`_SettingSlider` became the shared `SettingSlider`.** Settings › Reading
needed a control identical to the profile editor's "Rewind on resume", since
the step and the rewind are both "how many words". A third private slider would
have made a duplication the repo already had on record worse.

**A step while playing writes a position.** The save gate keys on the transition
into a stopped state, and a step from `playing` is one. Repeat steps while
already paused do not transition and so do not write, and `_close` catches the
final index. No new save path.

## Alternatives rejected

**Reuse `rewindWords` for the step.** One number, already synced, already in
the profile editor, and exactly what `arrowLeft` did. Rejected on section 3's
argument: the two answer different questions, and a reader who lengthens their
resume rewind has said nothing about how far a tap should move. It would also
have put the setting in the profile editor rather than on Settings › Reading.

**A new per-profile `stepWords` field.** Would sync and could differ per preset.
Rejected: `rewindWords` is a real column on `StoredProfiles` rather than a key
in the JSON blobs, so a second top-level field costs a schema bump, an
`onUpgrade` step, a `_revertTo` case, and a wire-format change — for a value
whose whole argument is that it should differ *between* devices, which is the
one thing syncing it would prevent.

**Left half / right half, no centre.** The simplest rule to explain. Rejected:
it removes the tap-anywhere-to-pause reflex the app is built around and leaves
elicited pacing with no surface advance at all.

**Equal thirds.** Bigger, easier edge targets, which is a real argument for a
low-vision reader. Rejected in favour of protecting the primary control: an
edge mis-hit costs one step, a centre mis-hit costs a place in a sentence.

**Two rows of controls, the existing three untouched.** Zero disturbance to
muscle memory. Rejected: it eats vertical space on a phone and puts a second
row of chrome over a background the reader chose, which is the opposite of what
ADR 0015's fill removal was for.

**The pilcrow for the paragraph jump.** `paragraph` (`0xe960`) is the picture of
"paragraph" and is what ADR 0019's name-it-by-role rule points at. Rejected: it
carries no direction, and both buttons have to read as *forward* before they
read as anything else, in a row where the reader's backward control is a zone
with no glyph. Transport glyphs, with two triangles for the longer jump.

**Reading the step through a `ReadingDisplayController` threaded into
`BookOpener`.** Rejected in section 3.

**Making the jump buttons clamp to the last token instead of disabling.**
Rejected: a control that is present and moves nowhere is worse than one that
says it cannot.

## Verification

`dart test` and `dart test -p chrome` in `packages/rsvp_engine`, 211 tests
green on both targets. Both new `TokenizedText` methods do integer index
arithmetic, which is the category ADR 0009 exists for.

`flutter test` in `app/`, 955 tests green, including 12 new ones in
`reader_tap_zones_test.dart` and a rewritten `reader_semantics_test.dart`.

`flutter analyze` clean, and `flutter build web` succeeded — analyze clean is
not the same as builds in this repo, on the `phosphor_flutter` precedent.

Two things the tests found rather than confirmed:

- **The sentence-end reasoning was wrong on first write.** It claimed a
  block-final `.` reports `paragraph`. `tokenized_text_test.dart` failed with
  `sentence`, and the doc comment and both tests were rewritten around what the
  tokenizer actually does. The behaviour did not change — matching both values
  is still correct — but the reason recorded for it was false.
- **Three semantics tests reached the surface through `RsvpView`.** They now
  read the centre zone by key. The three `tester.tap(find.byType(RsvpView))`
  calls elsewhere still passed, because the zone sits over the same point, but
  Flutter's hit-test warning showed they were no longer pressing what they
  named, and they were retargeted too.

The two new codepoints were checked against the `cmap` of the vendored
`Phosphor-Light.ttf` directly, rather than against the `phosphor_flutter`
package's map alone. A wrong codepoint renders as a box and fails nothing.

**A manual pass in Chrome**, using its device emulation for the mobile case,
against the web build. Every control described here was exercised by hand and
behaved as this file says: the edges stepping and stopping, the centre still
starting and pausing, the two jumps landing where they should and greying out
at the end, the step slider taking effect, and the resume after a step staying
on the word it stopped on.

**Still not run: anything on a physical device.** Emulation answers the
questions about layout and gesture regions and does not answer the one ADR 0019
left open, which is whether the Light weight holds up at 20-24dp against real
pixels rather than a scaled desktop panel. The five-button row was seen at a
mobile viewport, but a viewport is not a thumb. That gap, and the Android
Chrome gap the README already records for everything since the UI pass, both
stand.
