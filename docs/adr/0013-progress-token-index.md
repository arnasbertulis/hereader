# 0013. Reading progress is a stored token index

Date: 2026-08-15

## Status

Accepted.

## Context

`ReaderScreen` computes a token index on every save and hands it to
`savePosition`, which puts it in the outbox payload. ADR 0005 needs it there:
the service holds no copy of any book, so a client-supplied count is the only
way it can tell two devices that genuinely diverged from two devices a few
words apart, and the 500-token threshold is measured in it.

Until now that value had nowhere to land on the device that produced it. It
reached the service and was thrown away locally, so nothing in the app could
answer how far into a book a reader is without parsing the book again and
counting. `compute()` does not offload on Flutter web, so that parse runs on
the main thread, on the target where frames are already scarce, on whatever
screen asked the question.

A position can also reach a device long before its book does. ADR 0007 holds
those in `pending_positions`, and on web that path runs on every first
sign-in, so anything stored alongside a position has to survive the wait.

## Decision

### The token index is stored, on both position tables

`ReadingPositions.tokenIndex` and `PendingPositions.tokenIndex`, added in
schema version 6.

The value is the one `ReaderScreen` already computes. Nothing new counts
anything, and no import path changed: this is a column for a number that was
already crossing the wire.

### It is a hint, and never a locator

ADR 0002 puts navigation on `{blockId, charOffset, parserVersion}`, because a
tokenizer change moves every word index and nobody reports a bookmark that is
forty words off. A token index is exactly the quantity that argument rules
out.

So it is stored for comparison and display and read by nothing that decides
where to open a book. `positionOf` still returns a `Locator` and carries no
count. A stale index after a `kParserVersion` bump makes a progress readout
slightly wrong until the next save overwrites it, which is a different order
of problem from opening the wrong chapter.

### Nullable, with no default

Null and zero say different things. Null is that no count was recorded, which
describes every row written before version 6 and every event from a client
older than it. Zero is the first word of the book.

A default of zero would put every existing reader at the start of their book
with no way to tell that from a reader who is actually there. The migration
therefore adds the column and backfills nothing.

### A save writes the count it was given, including none

`savePosition` sets the column even when the caller passes null, rather than
leaving whatever was there. The count describes the position it arrived with.
Carrying the previous one forward would pair a count from where the reader
used to be with a locator for where they are now, and the service measures
divergence with that pairing.

### Held positions carry it through the wait

`_holdPosition` stores it and `_drainPendingPosition` moves it across with the
stamp and the timestamp it already carries. A book that lands on a device long
after the place in it does lands with the progress as well.

## Consequences

Progress becomes derivable as `tokenIndex / wordCount` at render time, from
two columns already on the device, with no parse. Three cases degrade and each
has an honest answer: a book never opened has no position row and no bar, a
position from a client older than version 6 has no count and no bar, and a
`wordCount` of zero is a pre-column book row that reports nothing rather than
dividing.

Nothing reads the column yet. The library summary and the tile are untouched,
and the read path lands with the screen that shows it.

The wire format is unchanged. The service has been receiving this number
since positions started syncing.

`resolveConflict` now writes the count locally as well as sending it. It was
sending the reader's chosen index to the service and writing the winning
position without it, which left the one device that settled a divergence as
the only device without the answer.

The migration test reconstructs an old schema version by building the current
one and undoing every step since, and version 6 is the first step that adds
rather than removes. The version 4 test failed on a duplicate column until
that reconstruction learned about the new step. Any future additive step needs
the same case, and a step that only drops something will not reveal a missing
one.

## Alternatives considered

**A character-offset ratio.** Rejected. `charOffset` is an offset inside one
block rather than into the book, so this means a cumulative character count,
and characters map to words at different rates across a book. Front matter,
verse, dialogue and tables tokenize at visibly different densities, so a bar
driven by characters advances at a rate the reader can see changing. It is
also derived from the same parser output the count is, so it buys no
independence from `kParserVersion`.

**Counting tokens in the background when the library loads.** Rejected on the
web target specifically. `compute()` runs synchronously on the main thread
there wrapped in a `Future`, so a library of twelve books parses twelve books
on the frame thread to draw a list. The real version of this idea is a web
worker, which is a larger piece of work and is listed as such.

**Storing a percentage rather than a count.** Rejected. The service's
divergence rule is in tokens, so a percentage would have to be converted back
using a `wordCount` the service does not have. It also loses precision for
nothing: the count is the number the client already holds.

**A column on `Books` instead.** Rejected on the same grounds as ADR 0004
separating positions from metadata. Progress is written on the position
cadence from ADR 0011, every fifteen seconds while reading, and book metadata
is written once at import under different conflict rules. Putting a
constantly-written value on the row that also holds the EPUB blob would mean
rewriting that row on every save.

**Making the column non-nullable with a default of zero.** Rejected above: it
would claim every pre-existing reader is at the first word.

## Verification

`flutter test` in `app/`, with `schema_migration_test.dart` building a version
5 database, upgrading it, and asserting that the stored place survives, that
its count is null rather than zero, and that a save after the upgrade stores
one. The last assertion exists because an `addColumn` against the wrong table
would leave the first two true.

`position_hint_test.dart` covers the repository paths: a save keeps its count,
a save without one clears the previous, a remote position stores what arrived
with it, a position held for an absent book keeps its count through the import
that drains it, and a remote position with no count still applies.

Not yet observed: an upgrade of a real install on a device. Everything above
ran against an in-memory or temporary-file SQLite database on Windows.
