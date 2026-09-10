# 0036. Chrome prose is budgeted in blocks: one sentence per control, one per section

Date: 2026-09-10

## Status

Accepted. The prose counterpart to ADR 0031 (type) and ADR 0033 (measure).

## Context

#352 counted ~710 words of explanatory prose across Settings for twenty
controls, for readers who find reading effortful. Most of what it described has
since landed: #402 moved 361 words behind `InfoDot`, ADR 0034 deleted Account
and Sync, and ADR 0031 §2 removed the `bodySmall` tier the prose was printed at.

**What never landed is the budget.** ADRs 0031 through 0035 cover type, colour,
measure, navigation and the reader transport; none covers prose volume, which
is the dimension that produced 710 words. The closest thing is `InfoDot`'s own
doc comment (`info_dot.dart:12`), which budgets the disclosure affordance — one
only where a setting is genuinely non-obvious — not the text on the page.

**Nothing in the code can hold a budget today.** There is no shared control
row. The Settings index has a private `_IndexRow` (`settings_screen.dart:428-461`);
the other screens use a bare `ListTile` (`reading_settings_screen.dart:97-100`).
Either takes any `Widget` as its subtitle, so a paragraph, a `Column` of
paragraphs or a second subtitle is one argument away.

A word count is the wrong test. It invites shrinking sentences rather than
removing them, and it cannot tell a label from an explanation.

## Decision

### 1. The budget is counted in blocks

A control carries its label and at most one supporting sentence. A section
carries its header and at most one supporting sentence. Nothing else is
printed. Anything more moves behind an `InfoDot` or is cut. A Browse problem is
a section: one sentence, then its action.

### 2. It covers every chrome screen except About

Settings and its destinations, Home, the Library, Free books, the note editor,
Paste and the Add menu. About is exempt: prose is its content. The reading
surface prints no prose at all under ADRs 0035 and 0037.

### 3. One row type carries the budget, and its supporting line is a `String`

Controls on covered screens are drawn with one shared row whose supporting line
is a `String`, not a `Widget`, so a paragraph or a column of text cannot be
passed to it. The sentence wraps and is never truncated: the budget is one
sentence, not one rendered line, and at text scale 2.0 a truncated line would
cut the sentence the budget exists to keep.

### 4. A test walks the covered screens

A widget test pumps each covered screen and counts printed text blocks per
control and per section. A free-standing `Text` outside a row or a section
header fails it, which is the case the row type in §3 cannot prevent.

## Consequences

- #352 becomes: introduce the row, convert the `ListTile` and `_IndexRow` call
  sites on covered screens, and add the test. The test finds whatever over-runs
  after #402; the per-screen targets in #352's original text are superseded.
- The budget does not license an `InfoDot` per row. `InfoDot`'s own rule — one
  only where a setting is genuinely non-obvious — stands beside this one.
- A new screen is checked against the budget by the test, not by a reviewer
  remembering it.

## Alternatives considered

- **A word budget per screen.** Rewards shorter sentences over fewer ones, and
  cannot distinguish a label from an explanation.
- **`maxLines: 1` on the supporting line.** Truncates at text scale 2.0, where
  this audience lives, cutting off the sentence it was meant to cap.
- **Per-screen targets, as #352 first proposed.** Superseded: two of the
  screens no longer exist, and a target per screen is ten call sites agreeing
  with each other instead of one rule.
- **Review only.** The 710 words were written by careful reviewers; convention
  is what produced them.
- **A simple/advanced switch.** Rejected in #352: it doubles the surface and
  asks for a meta-decision before the real one.

## Verification

The screen-walking test in §4, at text scale 1.0 and 2.0, green on every
covered screen. The row's constructor takes the supporting line as a `String`,
checked by the analyzer rather than a test.
