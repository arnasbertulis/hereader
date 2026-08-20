# 25. Continuous scroll is a second reading surface, driven by a ticker and dragged with a finger

Date: 2026-08-20

## Status

Accepted. Resolves the continuous-scroll paragraph in
[ADR 0003](0003-pacing-decision-model.md)'s Consequences, and supersedes in
part [ADR 0020](0020-reader-driven-navigation.md)'s three tap zones.

## Context

The app shows one word at a time at a fixed anchor. `PresentationMode` has
carried `continuousScroll` as an unimplemented value since the profile system
was written, and ADR 0003 predicted this work down to naming the paper that
had to be read first.

The evidence is the reason to build it rather than the reason it was
deferred. Fine & Peli (1995) found visually impaired observers reading 13%
*slower* from RSVP than from a scroll display — a difference that did not
reach significance, which is why the paper's own title reports the two
formats as similar rather than ranking them. Akthar et al. (2021) compared
static text, horizontally scrolling text and RSVP in simulated and actual
central vision loss, and found scrolling supported effective reading while
RSVP produced lower overall comprehension and high error rates. Both are now
in `docs/research/rsvp-evidence.md`, sections 2 and 6, with their PMIDs
checked against the journal record.

That is not evidence that scrolling is better. It is evidence that the
advantage RSVP shows over a page in sighted readers does not transfer to this
project's target reader, and that the literature declines to rank the two
formats for that reader. A tool built for central field loss that offers only
one of them is choosing on the reader's behalf with nothing to choose on.

The engineering problem is that the two formats want different clocks.
`PlaybackSession` advances on a chain of `Timer`s, each scheduled when the
previous one fires; the package README records the resulting overshoot as an
open item. A marquee that is not frame-accurate judders. And a per-token
`Hold.pauseAfter` applied as time would make the text surge and stall
mid-sentence, which is the failure ADR 0003 rules out in as many words.

## Decision

Numbered, because several of these are only correct together.

**1. The session keeps the position; the app supplies the time.**
`PlaybackSession` gains `tick(Duration)`, `scrubBy(double)` and a `double`
sub-token offset, and stays the single owner of *which token is current*.
Every existing path already reads that — the save gate, the four jumps,
`stopAt`'s rewind suppression, the progress bar, the chapter hint, the time
estimate — and two objects each holding a notion of the current token is a
failure this repo has on record twice.

A `ScrollClock` in `app/` owns a `Ticker` and calls `session.tick`. Nothing
in it keeps an index.

**2. The gate lives inside `_scheduleCurrent`, not at its six call sites.**
`bool get scrolling` is derived from the profile, so `profile =` switches
mode mid-read with nothing else to keep in step. `_scheduleCurrent` returns
early under scroll, before consulting `PacingModel`. Six callers is six
chances to miss one; gating in the callee makes every caller correct by
construction and leaves every `_timer?.cancel()` a harmless no-op.

**3. Scroll outranks pacing, and it does so once.** Because `_model` is never
consulted, `AwaitAdvance` is unreachable and an `elicited` profile simply
scrolls. There is no branch for it, deliberately, and this paragraph exists
so nobody adds one later.

**4. Geometry crosses the boundary as data.** The engine imports no Flutter
and measures nothing, so it is handed a `TokenRun` — per-token advances in
logical pixels, plus a mean for anything outside the window.

**5. Constant velocity is constant in pixels, not in tokens.** Word widths in
prose vary by more than 2:1, so stepping at a uniform token rate would
produce a velocity wobble of roughly ±40% at about 4 Hz — ADR 0003's "surge
and stall", reintroduced through the back door. The cursor steps over each
token's real advance while it is inside the measured window.

**6. Velocity is `(baseWpm / 60) × meanAdvance`.** No new profile field and
nothing new on the wire. `meanAdvance` is measured from the laid-out window
and is honest on average, the same caveat ADR 0003 already records for
`referenceLetterCount`.

**7. The sub-token offset is never persisted.** Locators are token-granular
(ADR 0002). A save writes the token index and discards the offset, so a
resume places the anchor at the token's leading edge rather than partway
through it — at most one word, and cheaper than a schema change, a wire
change and a server change to buy back.

**8. `stopHere()` is `stopAt` without the move.** A finger lifting off a
scrub must not snap: `stopAt` zeroes the offset, so routing drag-end through
it would jump the text by up to a word at the moment of release. `stopHere`
keeps the index and the offset and sets the same one-shot rewind
suppression, so ADR 0022's guarantee reaches a drag as well as a jump.
`pause()` deliberately keeps the offset too, because the finger landing
pauses before it drags.

**9. The window is never the book.** About sixty tokens are measured around
the anchor, asymmetric — more ahead than behind, because text enters from
the right — and re-measured only when the anchor nears an edge. Laying out a
whole book would cost a pass proportional to its length on the one platform
where `compute()` does not offload.

**10. One measurement, used twice.** `measureRun` returns a `ScrollLayout`
holding both the `TokenRun` the session walks and the `TextPainter`s the
widget draws. The widget is *told* which token is current and draws it at
`anchor − offset`; **anything that hit-tests a laid-out box against the
anchor to ask which token is current is a bug**, because that is the second
function that would eventually disagree.

**11. `ReadingSurface` is the one place that decides which surface a profile
draws**, and both the reader and the settings preview call it. `RsvpView`'s
doc comment records why the preview draws through the real surface: the
contrast readout sits beside it and measures what it draws, and it measured a
pair the app never painted until the preview was folded in. A second surface
reopens that hole one level up. The switch is exhaustive with no `default`,
so a fourth mode is a compile error at the one place that must handle it.

**12. The eye point is a caret beside the line, never on it.** A rule drawn
through the words obscures the one word the reader is trying to read, which
is the opposite of what an eye point is for, and at a glance it reads as an
`l` or an `I`. Three settings, all per profile:

- **Placement** — `above`, `below` or `both`, defaulting to both. Each caret
  points *at* the line, so one above is the mirror of one below rather than a
  different shape.
- **Style** — a solid triangle, the same triangle stroked, or a chevron with
  no base. Weight against a heavily tinted surface is a legibility question,
  and this reader is the one who can answer it.
- **Distance** — the blank between the line box and the caret's tip, in em of
  the type size. A setting rather than a constant, because how far a marker
  has to sit from the words to stop competing with them depends on the shape
  of the reader's field loss rather than on the type size. The same argument
  `anchorX` already makes for putting the eye point off centre.
- **Size** — `caretScale`, a multiplier on the wedge's drawn width and depth
  together, so the shape stays a wedge rather than stretching. Bounds named
  once, `PresentationConfig.minCaretScale`/`maxCaretScale`, so the editor's
  slider, the constructor's assert and `fromJson`'s wire clamp cannot drift
  apart the way three separately-written bounds eventually do.
- **Thickness** — `caretThicknessEm`, the stroke width for outline and
  chevron, floored so it survives a small type size on a low-density screen.
  Kept separate from size rather than folded into it: one number driving both
  would mean a reader who wants a bigger caret always gets a heavier line too,
  and the two questions — how big, how heavy — are independent ones. Inert
  for the filled style, which has no stroke, so the editor hides the control
  there rather than showing one that does nothing.

**Colour is the accent, guarded against the surface it sits on.** The reader
picks the accent and the background on two screens that know nothing about
each other, so `readerCaretFor` falls back to the chrome ink wherever the
accent cannot clear 3:1 — WCAG 1.4.11's bar for a control that is not text,
and the same rule and the same fallback the progress fill already uses. The
guard is one function, `readerAccentOn(background, …)`, which the progress
fill now calls with its track and the caret with `surfaceArgbFor`: those are
genuinely different backgrounds, and a caret judged against the progress
track would be measuring a pair it never sits on — the exact shape of the bug
`RsvpView`'s doc comment records.

**This is a second accented object on the reading surface**, which widens ADR
0015's one-accent-per-screen rule. Deliberate, and asked for: the caret is
the eye point, which is the single thing a reader of a moving line has to
find, and it is only ever on screen beside the progress fill while the text
is stopped.

**13. The contrast readout is unchanged.** It measures the ink against the
surface; the sliding surface draws that identical pair from those identical
functions. The caret is excluded from it for the same reason the fixation
letter is — it is a marker rather than text — and it does not need to be in
it, because unlike the fixation letter it carries its own 3:1 guard.

**14. The surface is one semantics node.** `onTap`, plus `onIncrease` and
`onDecrease` carrying the stepping the edge zones used to. The edges were a
screen-reader user's only way to step, and deleting them with no replacement
would regress the exact axis ADR 0020 was written to fix.
`SemanticsAction.increase` is the idiom for a control moving along a
continuum, which this surface literally is. No `liveRegion`: ADR 0020
declined one at four words a second, and sixty frames a second is not the
case that changes the answer.

**15. Reduce-motion is honoured, and warned about.** A continuously moving
surface is what the system preference exists to suppress. This reader chose
motion as their reading *method*, and silently falling back to a fixed anchor
would take away the thing they selected. Warn, don't block, as the contrast
readout and the fade warning already do.

**16. The mode is a profile field with a switch in the reader's sheet, and
the switch has to be reversible.** On a stored profile it edits the profile
in place. On a preset, turning sliding on forks it and adopts the fork,
mirroring what the editor already does rather than inventing a second rule —
named after the change, "Standard (sliding)", not "Standard (copy)" the way
`_CopyProfile` names an actual duplicate.

The first shipped version stopped there, and turning the switch back off
simply flipped the fork's own mode field — which left the reader on a profile
still called "Standard (sliding)" and now showing one word at a time, because
nothing undid the fork itself. Reported directly: the switch had a direction
that did not come back.

`app/lib/reading/mode_fork.dart` fixes it by pairing a fork to its preset **by
value**, not by a stored lineage field. Storing which preset a fork came from
would cost a column, a migration and a wire change to hold a fact that is
already derivable: a fork the reader has not otherwise touched *is* the
preset in every field but its id, name and mode. So turning sliding off looks
for a preset whose JSON matches the profile's own once the id, name, mode and
— for the looser of two comparisons — the caret fields are stripped out, and:

- **An exact match** (nothing touched but the mode) returns to the preset and
  **deletes the fork**. Nothing is lost by removing it.
- **A match once the caret fields are ignored** returns to the preset but
  **keeps the fork**, unselected. The caret controls exist only under
  sliding and only appear in the editor there, so adjusting them is the
  expected thing to do inside a fork, and deleting it would take the
  reader's choice with it. Turning sliding back on for that preset finds and
  reuses this fork rather than making a second one.
- **No match at all** is the reader's own profile, changed in some field the
  fork comparison does not ignore. The switch edits it in place, as it
  already did for any profile that is not built in.

Fails closed: comparing by value only ever produces a *false negative* — an
edited-in-place profile that happens to have drifted enough not to match its
origin — never a wrong preset. A false positive would delete or hand back a
profile the reader meant to keep; a false negative just leaves it as its own
thing, which is what it already was.

**17. Everything inert under scroll is hidden, not disabled.** The whole
pacing model goes — the kind control, length scaling and the three pause
sliders — because `PlaybackSession` branches on the mode before it consults
`PacingModel`, so none of them has anything to act on. So do `transitionMs`
and `orpHighlight`: there is no moment at which one word replaces another to
fade, and marking a fixation letter on moving text is a different feature
that is not built. Stored values are left alone, so switching back restores
them. ADR 0020 already argued that a control which is present and does
nothing is worse than one that is absent, and six greyed controls is a
section that reads as broken rather than as inapplicable.

The corollary is the part that was a live fault: **the reading speed is
enabled under scroll whatever pacing kind the profile carries.** It was gated
on `kind != elicited`, so a profile forked from an elicited preset onto
sliding greyed out the one control that actually sets its velocity.

**18. The time estimate is shown, elicited included.** Seconds per token
under scroll is `meanAdvance / velocity`, and substituting decision 6 gives
`60 / baseWpm` — the mean width divides out. That is exactly what
`remainingReadingTime` computes for constant pacing, so the caller
substitutes the kind rather than gaining an estimate of its own.
`PacingModel` still knows nothing about presentation, one function still
computes this figure, and the substitution is honest: under scroll the pacing
genuinely is constant.

**19. `chunkSize` is untouched.** The marquee shows many words and still
advances one, so the `chunkSize == 1` assert and its `fromJson` pin stay as
they are. `chunkSize` is held for the unbuilt `shiftingWindow`.

**20. No preset changes mode.** Akthar argues for *offering* scroll to the
central-field-loss reader, not for changing a preset whose default rests on
Arditi 1999 — a rate finding rather than a comprehension one.

## Consequences

**Finishing a book had to clear the caret as well as the line, and the first
version did not.** `RsvpView` blanks for free on reaching the end, because the
session emits a null token and drawing nothing is what a null token already
means to it. This painter is driven by an index and a measured layout rather
than by a token, so on `PlaybackState.finished` it kept drawing the last line
and the caret pointing at it, underneath the "End of book" notice. Fixed by
an explicit check in `MarqueePainter.paint`: finished clears both. Covered
with a canvas that counts draw calls rather than comparing pixels, with a
paired "still draws while merely stopped" test so it cannot pass vacuously.

**The 60Hz claim in both READMEs is now false and is corrected here.** Both
stated that reading is unaffected by Chrome-on-Android's main-frame throttle
*because RSVP replaces a word rather than animating*. Continuous scroll
animates, every frame, and is the first thing in this app that does. The user
has tested the case and accepts it: a 60Hz panel does not judder, and a 120Hz
Android panel drops to 60 after a few seconds without input, which aligns
with what `requestAnimationFrame` delivers. The mitigations are structural —
a `RepaintBoundary`, a painter driven by `CustomPainter(repaint:)` so no
widget rebuilds per frame, and advances measured about once every forty
tokens rather than per frame.

**A resume can shift the reader by up to one word**, per decision 7. Stated
here so it is not rediscovered as a bug.

**Right-to-left text is not addressed.** The run is pinned to
`TextDirection.ltr` rather than reading the ambient `Directionality`, because
an RTL ambient direction would mirror shaping *within* each token while the
run itself still travelled right to left — worse than being consistently
wrong. Recorded as a limitation in `app/README.md`.

**An old client renders a scrolling profile as a fixed anchor without
corrupting it.** ADR 0008 merges profiles whole, so a client that could not
read `mode` would write its fallback back. `continuousScroll` shipped as an
enum value in `v0.1.0`, so every build that exists resolves the name through
`enumByName` and preserves it through `toJson`. Only a build predating the
enum could lose it, and none was ever deployed.

**The screen-reader story is honest rather than good.** In scroll mode the
accessible navigation path is the control row — four jumps, play, the chapter
drawer, the progress bar — and the step actions on the surface. Continuous
scroll is a *visual* presentation and gives a screen-reader user nothing the
fixed anchor did not. Anyone who needs speech rather than sight is better
served by the whole book read aloud, which is the argument already written
into the reader.

**No migration, no server change.** `presentationJson` is a TEXT blob and the
sync payload is an opaque map; the server never inspects profile fields.

## Alternatives considered

**A separate `ScrollSession`.** Rejected: two objects would each hold a
notion of the current token, and every consumer — the save gate, the jumps,
the progress bar, the chapter hint — would have to ask the right one.

**Driving the existing `Timer` chain faster.** ADR 0003's own suggested
flattening: a pacing model returning `Hold(display: tokenWidth / velocity)`,
which leaves the session untouched. Rejected twice over. It hands the
marquee's timing back to the chain whose overshoot is a recorded open item,
and it needs a pixel width, which would force a Flutter measurement into a
package that must never import Flutter.

**Constant tokens per second.** Rejected by decision 5: a ±40% velocity
wobble at about 4 Hz is the exact artefact ADR 0003 refuses.

**`SingleChildScrollView` with a `ScrollController` over the whole book.**
Rejected: it lays out the entire book, which decision 9 exists to avoid, and
its ballistics are momentum-based, which a reader aiming at a particular word
does not want.

**`Transform.translate` over a `Row` of `Text` widgets.** Skips relayout but
churns forty widgets a frame, and puts the caret in a different widget from
the text, where the two can drift a pixel under different rounding.

**A vertical rule through the line.** What shipped first, and wrong: it
covers the word under it, and at a glance it reads as an `l` or an `I`. The
caret is the fix, and placement is a setting rather than a constant because
"beside the line" has three defensible answers.

**A second contrast guard for the caret.** Rejected: `readerAccentOn` takes
the background as a parameter and the progress fill now calls it too. Two
functions computing one figure is how they come apart; two *backgrounds* is a
real distinction and belongs in the argument list.

**Routing the caret through `readerProgressFillFor`.** Rejected: it measures
against the progress track, which is not what is behind the caret. That is
the exact bug `RsvpView`'s doc comment records, one object over.

**`orpArgb` for the caret.** The fixation-target precedent argues for it, but
it is a fixed red answering to neither the reader's accent nor their
background, and a guarded accent says what they picked.

**A stored field naming which preset a fork came from.** Rejected in favour
of comparing by value. A lineage field is one more thing every future caret
or presentation setting has to remember to leave out of the comparison
implicitly by not touching it, whereas the value comparison in
`mode_fork.dart` only has to be told explicitly which fields a fork is
allowed to differ in — and it already needs that list for the caret fields,
so extending it costs nothing a lineage field would not also have needed
updating for.

**Reusing `chunkSize` for the window size.** Rejected: it is held for the
unbuilt `shiftingWindow`, and overloading it would make a profile that syncs
in with `chunkSize: 3` mean two different things.

**A per-mode type size.** Rejected: one `fontSizePt` for both modes. A large
size on a phone shows few words at a time, and that is the accepted trade
rather than a second field to keep in step.

**Blocking under `disableAnimations`.** Rejected by decision 15.

**`Directionality.of(context)`.** Rejected by the RTL consequence above.

**Keeping three invisible zones for semantics only.** Rejected: a
screen-reader user would find three buttons where a sighted user finds one
surface, and decision 8 of ADR 0020 removed the zones as a concept here, not
as pixels.

**`onTapDown` to pause.** `BaseTapGestureRecognizer` defers it until the
recognizer wins the arena, the pointer lifts, or `kPressTimeout` — 100 ms,
which at 250 wpm is most of a word still sliding past after the reader has
touched the screen to stop it. A raw `Listener` sees the pointer immediately
and never joins the arena, so it takes nothing from the detector beneath it.

**A fling.** `onHorizontalDragEnd` ignores `primaryVelocity` entirely. The
reader stops where they let go; momentum would carry them past the word they
were aiming at.

## Verification

`dart test` and `dart test -p chrome` in `packages/rsvp_engine`: 265 tests,
both green. New coverage in `test/scroll_playback_test.dart` and
`test/token_run_test.dart` — equal elapsed times moving equal distance across
a clause, a paragraph and a chapter gap; a token crossing at its own advance
rather than at the mean; a scrub round trip returning to the same index and
offset; clamping at both ends; `stopHere` preserving the offset where
`stopAt` drops it; elicited plus scroll reaching `playing` and never
`awaitingAdvance`; a two-second paragraph pause changing nothing; the `run`
setter holding the anchor at the same fraction of the same word; and, under
`fakeAsync`, an hour elapsing with no timer moving the index.

**`test/playback_session_test.dart` passes unmodified**, which was the
acceptance gate on the engine design: `run` and the mode are settable
properties and `PlaybackUpdate.tokenOffset` defaults to 0, so no existing
construction site was touched.

`flutter test` in `app/`: 1057 tests, green. New files
`reader_scroll_gestures_test.dart`, `scrolling_surface_test.dart`,
`token_run_measure_test.dart` and `presentation_mode_test.dart`, plus a
sliding group in `reader_semantics_test.dart` and a per-frame rebuild guard
in `reader_progress_test.dart` asserting the reader's `Scaffold` widget is
the same instance across forty frames of motion. `reading_surface_test.dart`
and `reader_tap_zones_test.dart` pass unmodified.

`presentation_mode_test.dart` covers the reversible switch directly: a
preset forked and the fork named; the fork deleted on an exact-match
toggle-off and the preset re-selected; a fork carrying only caret changes
kept, unselected, and found again rather than duplicated; and a profile of
the reader's own, matching no preset, edited in place both ways.
`scrolling_surface_test.dart` covers caret scale and thickness as measured
path geometry — width and depth scaling together, stroke width driven only
by thickness, the two independent of each other — and the end-of-book case
above, off a canvas that counts draw calls.

`flutter analyze` clean and `flutter build web` succeeds — analyze clean is
not builds in this repo, on the `phosphor_flutter` precedent.

**Not run.** No frame measurement on a real Android device: this is the first
feature where `HEREADER_FRAME_STATS` would be load-bearing rather than
incidental, and the number is not in this ADR because nobody has taken it. No
manual pass on a physical phone, no trackpad, and no screen reader — the
`onIncrease`/`onDecrease` actions have the same standing as the keyboard
bindings ADR 0020 added, which have never met a real keyboard.
