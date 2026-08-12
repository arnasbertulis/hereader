# 0011. Positions are written while reading, and the outbox coalesces them

Date: 2026-08-12

## Status

Accepted.

## Context

A reading position reached the database exactly once per sitting: when the
reader popped the reader screen, `ReaderScreen` returned a `ReadingResult` and
`LibraryScreen` wrote it. Anything that ended a session without that pop —
a crash, a killed process, a closed browser tab — lost the place entirely.

Web is the worst case and not an edge one. A tab close does not reliably run
Flutter's dispose path, so the ordinary way to stop reading on the deployed
build is also the way that loses the position. The reader then opens their
phone and finds yesterday's chapter.

Writing more often is not free. `savePosition` runs a transaction and appends
an outbox event, and ADR 0005 already records that the event log grows without
bound and that compaction is neither implemented nor needed *at the scale this
will see*. Saving on every advance would be four events a second at 250 wpm —
roughly fifteen thousand an hour of reading — which moves that from a
statement about scale to a statement that is no longer true.

A third thing turned up while writing this. Playback does not stop when the
app is hidden. Backgrounding an Android session or switching browser tabs
leaves the timer running, so the reader returns to a paragraph that went past
without them. Today that is merely annoying. With periodic saving it becomes
the position that gets stored, which is worse than not saving at all.

## Decision

### Positions are written on deliberate stops, and every fifteen seconds
### between them

Written when the session enters `paused` or `finished` — which covers the
pause button, opening the chapter panel, jumping to a chapter, and switching
profile, since each of those already pauses — when the app is hidden, and when
the book is closed.

Between those, a timer writes every fifteen seconds if the token index has
moved since the last write. Fifteen seconds is about sixty words at 250 wpm.
A crash costs a sentence or two, which is close enough that the reader will
not notice, and small enough not to be worth naming in the interface.

The index guard is what makes the timer cheap rather than merely tolerable. A
reader who pauses to think, or who leaves a book open on a second monitor,
writes nothing at all: the tick compares two integers and returns.

The screen also no longer writes on open-and-close without reading. The last
saved index is seeded from the index the book resumed at, so closing a book
the reader only glanced at issues no stamp and queues no event. The exception
is a position that could not be resolved against this copy of the book, where
the index the reader is actually at *is* new information and is written.

### The outbox coalesces position events per book

A queued position event that has never been sent is deleted when a newer one
for the same book is enqueued.

This is a per-entity rule, like the conflict rules in ADR 0005, and it is a
statement about what the events mean rather than an optimisation. Profile
events are distinct facts: a create, a rename and a deletion each carry
something no other event carries, and dropping one loses it. A position event
says only "the reader is here now". The service resolves to the latest, every
other device wants only where the reader ended up, and an intermediate
position has no consumer anywhere in the system.

So the outbox is an append-only log for profiles and a latest-value queue for
positions. With that, save cadence stops mattering to sync volume: whether the
timer fires four times or four hundred, the queue holds one event per book,
and the number of events the service ever sees is the number of times the
reader genuinely stopped.

Only events with `attempts == 0` are coalesced. An event that has already
failed keeps its row and its counter, so the parking behaviour that stops a
poison event blocking everything behind it is untouched. The cost is that a
transient network failure can leave two or three queued positions for one
book, which is bounded by the parking limit and resolves the same way any
other duplicate does.

Coalescing cannot race a push. A send in flight already holds the rows it read;
deleting one here means `markSent` deletes nothing for that id, and the
replacement is picked up on the next drain.

### Being hidden pauses playback

`AppLifecycleListener` pauses the session and saves when the app is hidden.

Without it, periodic saving would make an existing bug worse rather than
better: the stream advancing behind a switched tab already carries the reader
past text they did not see, and the whole point of this document is that the
place it reaches now gets written down.

### `ReaderScreen` decides when to save; the library decides how

The screen took a `ReadingResult` out through the route's pop value, and the
library wrote it. It now takes an `onSave` callback and the pop carries
nothing.

Two paths writing one fact is how they come apart — the same argument as the
duplicate reading surface in the settings preview. The screen is the only
thing that knows the reader has stopped; the repository is the only thing that
knows how a position reaches disk and the outbox in one transaction. Neither
needs the other's knowledge.

It also makes the paste screen honest. Pasted text has no book row and a
position against it would fail the foreign key, so it passes a callback that
does nothing, rather than relying on its caller discarding a returned value.

## Consequences

Sync volume is unchanged from before this document, despite far more writes.
Every extra write lands on a row that replaces a row.

A hard kill still loses up to fifteen seconds. This is a smaller number than
the old failure and not zero, and the README says fifteen seconds rather than
implying none.

A browser tab closed outright may lose more than that. `AppLifecycleListener`
fires on visibility changes, so switching tabs saves, but a tab killed without
a hidden state gets no callback and falls back to whatever the last periodic
write recorded. Not solved: the reliable fix is a `beforeunload` handler,
which is a web-only path with no equivalent on the other targets.

Every save issues an HLC stamp, and `issueStamp` persists it through
`setPreference`. So a periodic save is two writes rather than one. Both are
small and both are already on this path; noted because it is not obvious that
stamping is not free.

The pause-on-hide changes behaviour a reader may notice: switching away from
the app mid-stream and back now returns them to the word they left rather than
sixty words further on. That is the intended reading of it.

## Alternatives considered

**Save on every advance.** Rejected on volume, above. Coalescing would in fact
make it survivable, but a transaction per word is work the device does not
need to do for information nobody consumes.

**Periodic saves local-only, with sync events at deliberate stops.** Rejected.
It sounds conservative and it makes the crash case worse in exactly the wrong
way: the device that crashed holds the correct position, and every other
device gets the one from the last time the reader deliberately stopped, with
no way to tell that it is stale. Coalescing gets the same volume without
splitting one write into two kinds.

**Coalescing every unsent position event regardless of `attempts`.** Rejected:
it would reset the counter on a failing event each time the reader moved, so a
genuinely poison position could never be parked, which is the failure ADR 0007
built parking to prevent.

**Coalescing profile events the same way.** Rejected. A queued create followed
by a queued deletion are not the same fact stated twice, and collapsing them
would push a tombstone with no create behind it. The asymmetry is the
substance of this section.

**Saving from a `WidgetsBindingObserver` rather than
`AppLifecycleListener`.** Rejected as the older interface with no advantage;
the listener gives the specific transitions rather than a state enum to switch
on.