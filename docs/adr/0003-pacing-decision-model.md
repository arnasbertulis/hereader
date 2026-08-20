# 0003. Pacing returns a sealed decision, not a duration

Date: 2026-07-30

## Status

Accepted.

## Context

The RSVP engine must decide how long each token stays on screen. Three
findings in `docs/research/rsvp-evidence.md` rule out a single answer:

- Aquilante et al. 2001 (*Optom Vis Sci* 78(5):290-6) found that scaling word
  duration by word length gave central-field-loss readers a 33% improvement,
  while normally-sighted older readers read fastest at a constant rate. Two
  populations, opposite results.
- Arditi 1999 (*Vision Research* 39(26):4412-8) found that letting the reader
  advance each word with a button press beat fixed-rate RSVP by 47% in slow
  low-vision readers, with the benefit disappearing above 133 wpm.
- Rayner et al. 2016 (*Psych Sci Public Interest* 17(1):4-34) rules out any
  claim that one rate suits everyone.

So pacing has to be a per-profile setting with at least three behaviours:
`constant`, `lengthScaled`, and reader-driven `elicited`.

The obvious interface is `Duration durationFor(Token)`. It breaks on the third
case. A reader-driven advance has no duration at all; the word waits for input
that may never come. Encoding that as `Duration.zero` overloads one value with
two meanings, and every caller then has to know which meaning applies. Using a
sentinel such as `Duration(days: 365)` is worse, because the playback timer
would still be armed.

A second problem: word display and the pause that follows punctuation are
different things on screen. The word is visible for one interval, then the
anchor position goes blank for another. Collapsing them into one number makes a
sentence boundary indistinguishable from a slightly longer word.

## Decision

### 1. Pacing returns a sealed `PacingDecision`

```dart
sealed class PacingDecision {}

final class Hold extends PacingDecision {
  final Duration display;
  final Duration pauseAfter;
  Duration get total => display + pauseAfter;
}

final class AwaitAdvance extends PacingDecision {}
```

The playback state machine switches on the variant. Dart's exhaustiveness
checking on sealed classes means adding a fourth pacing behaviour later
produces a compile error at every site that must handle it, rather than a
silent fallthrough.

`Hold` keeps `display` and `pauseAfter` separate so the renderer can blank the
anchor during the pause.

`ElicitedPacing` ignores punctuation entirely and returns `AwaitAdvance` for
every token. A reader pressing the button already encodes their own pauses;
adding a forced delay on top makes the control feel unresponsive.

### 2. `lengthScaled` normalizes against a reference letter count

Naive scaling multiplies the base duration by the word's letter count. The
implied reading rate then depends on the average word length of whatever the
reader opened, so a setting of 250 wpm produces a different actual rate for
Lithuanian text than for English. The number in the settings screen would not
mean anything.

Instead the model scales against `referenceLetterCount` (default 5.0):

```
factor = 1 + strength * (letterCount / referenceLetterCount - 1)
```

At the reference length the factor is 1, so `lengthScaled` and `constant` agree.
At `strength = 0` the model degenerates to `constant`, which gives a continuous
knob rather than a hard mode switch.

### 3. `PacingModel` knows nothing about presentation

Pacing decides *when* to advance. The renderer decides *what appears on screen*
— a single token at a fixed anchor, a short window of words that shifts by one
on each advance, or something else. These are orthogonal axes, and the profile
carries `PresentationMode` separately from `PacingModelKind`.

Only fixed-position single-token rendering ships now.

## Consequences

Discrete-shift rendering (a context window that steps left one word per
advance) consumes `Hold` and `AwaitAdvance` unchanged. It is a renderer change
only, which is why `chunkSize` sits in the profile rather than in the engine.

Continuous smooth scrolling cannot reuse this engine. A ticker needs constant
velocity; honouring a per-token duration would make the text visibly surge and
stall mid-sentence. Continuous scroll therefore requires either its own pacing
path or a flattening of per-token timing into a single velocity.

**Resolved by [ADR 0025](0025-continuous-scroll.md).** The second option was
taken: continuous scroll flattens per-token timing into a single velocity,
`(baseWpm / 60) × meanAdvance`, and there is no second pacing path.
`PacingDecision` and `PacingModel` are untouched, and section 3's separation
of pacing from presentation stands — `PacingModel` still knows nothing about
what a surface draws.

What did move is where the boundary sits. **`PlaybackSession` now branches on
`PresentationConfig.mode` before consulting the model**, at the top of
`_scheduleCurrent`, so under continuous scroll `_model.decide` is never
called: `Hold.pauseAfter` is not honoured as time and `AwaitAdvance` is
unreachable rather than handled. That is a narrowing of section 3's boundary
and it belongs stated here rather than left as a comment. The session, not
the model, is what knows about presentation.

Fine & Peli (1995) and Akthar et al. (2021) are in
`docs/research/rsvp-evidence.md`, sections 2 and 6, with their PMIDs verified
against the journal record.

`referenceLetterCount` is honest only on average. A book whose mean word length
differs sharply from 5 will still read faster or slower than the configured
`baseWpm`. Per-book calibration against the actual mean is deferred; the
paragraph-level test in `test/pacing_paragraph_test.dart` will fail if the
mismatch grows large, which is the signal to revisit.

The package keeps the name `rsvp_engine` even though `PacingModel` is
presentation-agnostic. Renaming costs more than the ambiguity is worth.

## Alternatives considered

**`Duration durationFor(Token)` with a sentinel for elicited.** Rejected: one
value carrying two meanings, and every caller has to remember which.

**Separate interfaces for timed and untimed pacing.** Rejected: the profile
system needs a single `PacingModelKind` field, and two interfaces would push
the branch up into profile loading instead of the one place that handles it.

**Nullable return (`Duration?`, null meaning wait).** Rejected: works, but
carries no room for `pauseAfter`, and null is a weaker signal than a named type
at the point where a reader is waiting on a button that may never come.
