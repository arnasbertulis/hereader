# 0007. Positions for absent books are held, not dropped

Date: 2026-08-06

## Status

Accepted.

## Context

ADR 0004 keeps book files on the device and syncs only positions. ADR 0005
says a reader who imports the same book on two devices gets a shared
position. Neither addressed the interval between those two facts: a position
event arrives for a book this device has not imported.

`reading_positions.book_id` references `books.id` with a delete cascade, and
`beforeOpen` sets `PRAGMA foreign_keys = ON`, so the insert fails outright
with SQLite error 787 rather than writing an orphan row.

The failure reproduces exactly on a fresh web sign-in against an account that
has been reading on Windows. It is not an edge case on that target: books
never transfer, so every web client meets it on its first pull.

The same trace explained the sync indicator that spun indefinitely.
`syncNow()` caught `NetworkException` and `ApiException` and nothing else, so
a drift error escaped both clauses and skipped the final status emit. The
last state on the stream stayed `syncing`. `_pullRemote` also writes
`sync.last_seq` only after applying a batch, so the sequence never advanced,
every later attempt pulled the same event, and the device wedged permanently
rather than recovering on the next tick.

Three things could happen to a position whose book is absent.

**Drop it.** Clients pull everything after `lastSeq`, and `lastSeq` advances
past the skipped event. The position becomes unreachable. A reader who
imports that book later starts at the beginning with no sign that a position
ever existed, which ADR 0005 already argues is the failure readers notice.

**Remove the foreign key.** Positions would write freely, at the cost of the
cascade ADR 0004 relies on for deletion. Orphan rows would accumulate for
every book ever removed.

**Hold it until the book arrives.** Costs a table and a drain step.

## Decision

### Positions for absent books go to `pending_positions`

A separate table keyed by `book_id`, carrying the locator fields, the
originating stamp, and the original timestamp. It has no foreign key. That
absence is the reason the table exists rather than an oversight.

`applyRemotePosition` checks for the book first, reading only the id column
so the check does not pull an EPUB blob into memory to answer a yes-or-no
question. Book present, and the position writes to `reading_positions` as
before. Book absent, and it upserts here, keeping whichever HLC is greater.
Stamps are fixed-width, so a string comparison gives the same order as
comparing the parts.

### Import drains the held row in the same transaction

`addBook` inserts the book, then moves any held position into
`reading_positions` and deletes the held copy, inside one transaction. A book
that reached disk while its position stayed behind would open at the start
and then jump the moment the next sync ran.

The drain carries the original stamp and timestamp across rather than issuing
new ones. That write happened on another device at that time; restamping it
here would let an old place outrank a newer read elsewhere. It writes no
outbox entry either, for the reason `applyRemotePosition` does not: the
service already has this event.

### The pull loop isolates failures and always resolves its status

Push already parks an event the service refuses so nothing queues behind it.
Pull had no equivalent, and one rejected insert stalled every device it
happened to.

Each event is now applied inside its own catch. A failure is counted and
skipped, and the run continues. Skipping loses that one change; stalling
loses every change after it, permanently, which is the worse trade.
`NetworkException` and `ApiException` still propagate, because those describe
the connection rather than the event.

`syncNow` gains a catch-all that emits a failed status. An indicator that
spins forever claims work is happening when none is, and a reader cannot tell
that from slow.

The pull loop also returns when a batch comes back empty, regardless of
`hasMore`. A service reporting more to come while sending nothing would spin
that loop with the indicator running throughout.

## Consequences

Schema moves to version 3. The migration adds one table and touches nothing
existing, so an install on version 1 or 2 steps through in order and keeps
its books. It runs identically against OPFS on web and native SQLite
elsewhere. Worth verifying against a database that already holds data rather
than only a fresh one.

A held row for a book the reader never imports stays until sign-out clears
it. Each is a locator and two integers, so the space is not worth reclaiming
on a schedule.

Deleting a book locally and later re-importing the same edition restores the
synced position through this path, since the event returns as held. That
matches what a reader would expect and was not designed for deliberately.

A skipped event is genuinely lost: `last_seq` moves past it and no later pull
returns it. Position events can no longer fail this way, so what remains is a
malformed payload from a future client, which would fail identically on every
retry. The count surfaces in the sync status rather than disappearing.

## Alternatives considered

**Ask the service for a book's current state at import time.** The service
holds resolved state per entity, so importing could request the position
directly. Rejected as the primary mechanism: import must work offline, and a
position that arrived earlier still needs somewhere to wait. Worth adding
later for a device importing a book it has never synced.

**Insert a placeholder book row to satisfy the constraint.** Rejected. A row
in `books` with no bytes would appear in the library as a book that cannot be
opened.

**Drop the foreign key and clean up orphans on a schedule.** Rejected: trades
a guarantee SQLite enforces for a job that has to run and be correct.
