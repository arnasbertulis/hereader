# 0037. Transport controls are named in a legend, and the tap is taught on the first Play

Date: 2026-09-10

## Status

Accepted. Supersedes ADR 0035 §2 and §3, and the first sentence of its
Verification. ADR 0035 §1, §4 and §5 stand. ADR 0021's four jumps, two rows and
glyphs are unchanged.

## Context

ADR 0035 §2 put a visible text label under every transport control, and §3
named the seek pairs by axis. #415 shipped both: "Paragraph" and "Sentence"
under the seek pairs, and "Back to library", "Read"/"Pause" and "Reading
profile" under the book-level row, plus "Chapters" when the book declares
chapters.

**The labels are paid for on every pause, for the reader's whole life, and
earn their keep in the first few sessions.** #445 reports the row as bloated:
five or six words of chrome over a surface whose only job is to hold one word
still. Close, Play and Profile are conventional glyphs. The one pairing a
reader cannot recover from the glyphs is sentence against paragraph, and that
is a thing learnt once, not read every time.

**ADR 0035's objection was to tooltips, not to disclosure.** Its §2 rests on "a
tooltip is not a label": a pointer affordance is never drawn on touch, so the
names never reached the audience this app is for. A legend opened by a tap is
drawn on touch. It meets the objection §2 answered without charging every
pause for it.

**While playing, the surface is already only the word.** `reader_screen.dart:1121`
is `showControls = state != PlaybackState.playing`, and everything gated on it
leaves the tree. A tap anywhere toggles playback, so the way back from an empty
screen exists — it is the same tap — but nothing teaches it (#435). A reader
who taps by accident sees the chrome vanish and has no visible reason to tap
again.

**The glyphs pair against media-player convention.** ADR 0021 §3 gives the
sentence jumps Phosphor's `skip-back`/`skip-forward` and the paragraph jumps
`rewind`/`fast-forward`. On a media player, skip is the larger unit (a track)
and the double chevron is a scrub. The mapping has a reason — ADR 0021 §1 gives
the sentence jump skip-back's "restart what I'm on" rule — but it means the
glyphs alone suggest the opposite sizes. The axis labels were covering for
that.

## Decision

### 1. No transport control draws a text label

Supersedes ADR 0035 §2 and §3. Each control's name lives in two places: its
`Semantics` label, for assistive technology, and the legend in §2. The name
strings do not change. Hierarchy on this surface is still size and position
(ADR 0035 §1).

### 2. The names live in a legend behind one (i) in the top right

An `InfoDot` in the top-right corner of the reading surface, with the
accessible label "About the reading controls". It opens a sheet listing every
control currently on the row — glyph, name, one line of what it does — and the
two gestures that have no glyph: tap anywhere to play or pause, and drag
sideways to move through the book. Chapters is listed only when the book
declares chapters, so the legend never names a control the reader cannot find.

The (i) is chrome. It is shown only while paused, like everything else, and
closing its sheet does not start playback (ADR 0035 §5).

### 3. While playing, the surface is only the word

No persistent target, no faded chrome, no progress line. This records the
behaviour `reader_screen.dart:1121` already has, as a rule, so that the next
reader to notice an empty screen finds a decision rather than an omission. The
fixation point is what this surface exists to hold still, and anything drawn
beside it while playing competes with it.

### 4. The first Play teaches the way back, once per device

The first time playback starts on a device, one line — "Tap anywhere to pause"
— shows clear of the word and dismisses itself after a few seconds, or on the
tap it describes. It is the one thing drawn while playing, once. Whether it has
been shown is device-local state and never synced: learning a gesture is a
habit of the device, and a hint shown twice costs little.

## Consequences

- Closes #445 and #435 once implemented.
- The seek row loses its label line, returning that height to the reading
  surface on a 320-high viewport — the constraint ADR 0035's Consequences
  asked to check first.
- **The sentence/paragraph distinction now has exactly one visible home: the
  legend.** If readers confuse the pairs, the repair is the glyphs (ADR 0021
  §3), not the labels. Recorded so the question is reopened in the right
  place.
- #413's test changes claim. It no longer asserts rendered label text. It
  asserts that every transport control has a non-empty `Semantics` label, that
  the legend lists every control currently on the row — Chapters only when
  present — and that the (i) is absent while playing. All through this
  project's keys.
- ADR 0021's amendment stops drawing a jump that cannot move. The legend still
  lists all four jumps; it describes the controls, not their current state.
- The legend is a disclosure under ADR 0036, not printed prose, so it sits
  outside the per-control budget.

## Alternatives considered

- **Keep ADR 0035's labels.** The cost is paid on every pause and the benefit
  is concentrated in the first sessions; the legend gives the same names on
  touch without the standing cost.
- **Shorten the labels** ("Library", "Profile"). Less bulk, same standing cost,
  and it spends words on the glyphs that least need them.
- **Drop the book-level labels, keep the two axis labels.** Keeps the one
  distinction the glyphs do not carry. Rejected on #445: two words under the
  seek row still read as the bloat, and the distinction is learnt once — which
  is what a legend is for.
- **Swap the glyphs so skip is the paragraph jump.** Loses the restart
  semantics ADR 0021 §1 matched to skip-back, and breaks the verified mirror
  pairs of ADR 0021 §3 for a convention that is itself inconsistent across
  players.
- **Leave one faint target on screen while playing.** Competes with the
  fixation point, which is the defect this surface exists to avoid.
- **Teach the tap on first open.** Read before the reader has pressed Play, so
  before it means anything.
- **Print "Tap anywhere to play or pause" permanently while paused.** Paid on
  every pause, and a standing line of prose over the ADR 0036 budget.

## Verification

Widget tests: every transport control has a non-empty `Semantics` label and no
`Text` descendant; the (i) is present while paused and absent while playing;
the legend lists each control on the row, with Chapters present only for a
chaptered book; closing the legend leaves playback paused; the first-Play hint
shows on the first Play only, and not after the stored flag is set. A manual
pass at 320 wide in Chrome's touch emulation, checking the (i) does not collide
with the title and the hint does not overlap the word at the largest profile
type size.
