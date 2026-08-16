# 0014. Time left is estimated from the active profile, and withheld under elicited pacing

Date: 2026-08-17

## Status

Accepted.

## Context

Home's continue tile answers where the reader was. The question a reader
picking a book up again asks next is how much of it is left, and the app had
no answer to it anywhere.

ADR 0013 made one possible without a parse. `ReadingPositions.tokenIndex`
holds how many tokens into the book the stored position is, `Books.wordCount`
holds how many there are, and `BookSummary` already carries both. The
difference is the tokens still ahead.

Turning tokens into minutes needs a rate, and this app does not have one rate.
Pacing is a per-profile setting with three models behind it (ADR 0003), one of
which has no duration at all: elicited pacing waits for the reader and
`PacingDecision` says so by returning `AwaitAdvance` rather than a `Hold` of
zero.

## Decision

### The estimate is tokens times the profile's own per-token hold

`remainingReadingTime` in `rsvp_engine`, taking a token count and a
`PacingConfig`, multiplying the count by `referenceDisplay`. That function
already exists, already applies `minDisplay` and `maxDisplay`, and is already
what the settings screen uses to warn that a fade outlasts a word, so the
estimate and the warning cannot disagree about how long a word is shown.

In the engine rather than the app for the reason ADR 0009 gives: it is
arithmetic, the suite there runs under `dart2js` as well as the VM, and
`app/test/` cannot run in a browser at all.

### Under elicited pacing there is no estimate

`remainingReadingTime` returns null, and the tile shows the count of words
left instead of a time.

Nothing moves under elicited pacing until the reader presses, so any figure in
minutes is a claim about the reader rather than about the book. Filling it
from a published average is the same move ADR 0010 refuses when it declines to
build a chapter list out of heading blocks: a plausible answer that nobody
checked is worse than the absence of one, because the reader cannot tell which
they are looking at.

### The estimate is stated as short, and left short

A real run adds a clause, sentence or paragraph pause after some tokens.
Which tokens those are is a property of the parsed book, and ADR 0004 stores
the EPUB rather than the parse, so a screen outside the reader has the count
and not the tokens. Reaching for them means parsing on the main thread of the
target where `compute()` does not offload.

Nothing corrects for this. A fixed uplift would be a second guess layered on
the first, and the error is a few percent on a figure already rounded to the
minute.

### A book never opened is estimated whole

`tokenIndex` is null there, and zero tokens read is what that means for this
question. It is not what it means for the question `progressOf` answers, which
still reports the book as unstarted and draws no bar, so the two are computed
separately rather than one deriving from the other.

## Consequences

Home reads the active profile, which it did not before. The pointer is a
preference and the profile it names is a row, so a screen that read it once
would go stale on two separate writes: choosing a different profile, and
editing the active profile's pacing. `LibraryRepository.watchActiveProfile`
joins the two tables for the tables rather than for the columns — drift
invalidates a query stream on any write to a table the query reads — and
discards the row, because a built-in preset has no row to return.

The tile falls back to `progressOf`'s words in three cases, each of which the
reader can tell apart: elicited pacing shows words left, a book whose
`wordCount` predates the column shows "Not started" or "In progress", and the
frame before the first profile emission shows the same.

The estimate moves when the reader retunes their profile, which is correct and
will look like a bug the first time someone sees a book gain half an hour.

## Alternatives considered

**An average reading rate for elicited profiles.** Rejected above. The number
would be indistinguishable from a measured one on screen.

**Measuring the reader's actual rate.** Not rejected on the merits — it is the
better answer and it needs data the app does not collect. Positions are
written every fifteen seconds while the index moves (ADR 0011), so the raw
material for a measured rate is already crossing that path, and this is worth
returning to.

**Storing an estimate with the position.** Rejected. It is derived from two
columns already on the device and a profile that changes independently of
both, so a stored copy would be wrong from the first profile edit.

**Counting real pauses by parsing the book.** Rejected on the web target
specifically, for the reason ADR 0013 rejects counting tokens at library load:
`compute()` runs on the main thread there, and this would parse a book to draw
a list.

**Formatting the figure in the engine.** Rejected. Minutes and hours in
English is presentation, and `rsvp_engine` carries no strings a reader sees.
`remainingLabel` in `book_progress.dart` does the wording, next to the words
`progressOf` already supplies for the cases with no figure.

## Verification

`dart test` and `dart test -p chrome` in `packages/rsvp_engine/`, with
`reading_time_test.dart` covering the arithmetic at 250 wpm, the equality
between length-scaled and constant at reference length, the null under
elicited pacing, `minDisplay` bounding a rate faster than it allows, and both
degenerate counts.

`flutter test` in `app/`, with the smoke test asserting that a stored book
with a word count and no position shows a figure in the tile rather than
reporting itself unstarted.

Checked by hand on Windows: the figure on Home follows a profile change made
in Settings without leaving the tab, follows one made in the reader's own
profile sheet on returning to Home, and shows words rather than minutes under
the elicited preset.
