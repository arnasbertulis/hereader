# 0005. Sync is an event log with per-entity conflict rules

Date: 2026-08-03

## Status

Accepted.

## Context

A reader with two devices should find the same place in a book on both. The
app is offline-first: reading must work with no network, so writes cannot
block on the server and conflicts are unavoidable.

Three broad approaches were available.

**Field overwrite.** Each device PUTs its current state; the server keeps the
last one received. Simplest possible design, and wrong for this data: a device
that has been offline for a week overwrites a week of reading with a stale
position the moment it reconnects.

**Conflict-free replicated data types.** Structure the data so concurrent
edits merge deterministically and conflicts cannot occur. Genuinely elegant,
and the right answer for collaborative editing. Overkill here: the contested
value is one person's position in one book, not two people editing the same
sentence.

**Event log.** Clients append immutable events; the server orders them and
hands them back. This is the mainstream approach for consumer sync and the
one chosen.

Within the event log approach there is a further choice: is the server a dumb
store that hands events back and lets clients resolve, or does it understand
entities and resolve centrally?

## Decision

### The server stores the log and maintains resolved state

Both. Events are appended to `sync_events` and are the source of truth.
Alongside that, `entity_state` holds the current resolved value per entity.

A dumb log would require every client to implement identical resolution rules,
and one client's bug would corrupt state everywhere. Central resolution keeps
the rules in one place.

Keeping the log as well means a device that has been away briefly pulls only
what changed, while a device that is far behind can take current state
directly rather than replaying a thousand events to learn one position.

### Ordering uses hybrid logical clocks, clamped by the server

Wall clocks disagree across devices, so "latest timestamp wins" can pick the
older write. Pure logical counters order correctly but lose any relation to
real time, so nothing can be shown to a user.

A hybrid logical clock is a wall-clock millisecond, a counter that increments
when writes land in the same millisecond, and a device id to break remaining
ties. It sorts lexicographically, stays close to real time, and never moves
backwards even if the system clock does.

Format: `{millis:013d}-{counter:05d}-{deviceId}`.

**The client supplies the HLC, so the server does not trust it.** A device
with a skewed clock, or a hostile one, could claim a stamp far in the future
and win every subsequent comparison permanently. The server rejects any stamp
more than five minutes ahead of its own time and records its own receive time
alongside the client's claim.

### Conflict resolution differs by entity type

One policy does not fit the data. This is the substantive decision in this
document.

| Entity | Rule | Why |
|---|---|---|
| Preference | Last write wins | A stale font size costs nothing. |
| Profile | Last write wins | Same, with more fields. |
| Bookmark | Tombstone on delete | A row that vanished entirely would be resurrected by any device that was offline when the deletion happened. |
| Reading position | Surfaced when divergence is large, last write wins otherwise | Being dropped in the wrong chapter is the failure a reader actually notices. |

Reading position is the case worth stating plainly. Two devices that differ by
a few words are the same position for practical purposes and resolve silently.
Two devices that differ by a chapter mean the reader read on both, and the
correct action is to ask which they want, not to guess. This is what Kindle
does with furthest-page-read, and for the same reason.

Measuring that divergence needs a distance the server can compute. It has a
block id and a character offset, which say nothing about how far apart two
positions are without knowing the book's structure — which the server
deliberately does not have, since book files never leave the device.

So the client sends its token index alongside the locator, purely as a
divergence hint. The server thresholds on the difference: under 500 tokens,
roughly two minutes of reading, resolves silently; beyond that, a conflict is
recorded for the reader to settle.

The hint is denormalized and unverifiable. That is acceptable because nothing
security-related depends on it: a wrong value causes a conflict prompt that
was not needed, or misses one that was. The locator itself remains the
authoritative position.

### Writes are idempotent by client-supplied key

Every event carries a key that is stable across retries. If a response is lost
and the client resends, the server recognises the key and does not apply the
event twice. Enforced by a unique constraint on `(user_id, idempotency_key)`
rather than by application logic, so the guarantee does not depend on getting
a check-then-insert right under concurrency.

### The user id comes from the token, never the request

An event's owner is whoever the validated token says it is. Accepting a user
id from the body would let any account write into any other account's stream.

## Consequences

More code than field overwrite: an outbox on the client, sequence assignment
on the server, resolution rules per entity, and a conflict surface in the UI.
All of it needs tests, because sync bugs appear only under conditions that are
awkward to reproduce by hand.

Book files are not synced, only positions and preferences. A book must be
imported on each device that reads it. See ADR 0004.

The event log grows without bound. Compaction — dropping events that are
already reflected in `entity_state` and older than any device's last pull —
is not implemented and is not needed at the scale this will see.

For a single reader with two devices, most of this machinery is more than the
problem requires. It is here because sync is the part of this project that is
worth building carefully, and because the per-entity rules above are a real
design judgment rather than a library call.

The divergence hint is for the service and not for the reader. Building the client made the distinction sharper than this document originally put it.

The token index a client sends is unverifiable, which is acceptable for a threshold: a wrong value costs a prompt that was not needed, or misses one that was, and the locator remains the position either way.

It is not acceptable as something to show a reader. An early version of the conflict sheet displayed the hint, so a candidate labelled "30% through" landed the reader at 4% when the hint and the locator disagreed. Promising a place and then going somewhere else is worse than not asking at all.

The app therefore resolves both candidates against its own copy of the book before showing them. It has the book; the service does not. A position whose block is absent from this copy is shown as unusable rather than offered.

The same reasoning applies to labelling. The service's ours is whichever write last won, which is not reliably the device asking. Candidates are described by where they are in the book rather than which device wrote them.

## Alternatives considered

**Firebase or another sync-as-a-service.** Rejected: it would remove the part
of the project worth building, and last-write-wins on a document is exactly
the behaviour that gets reading positions wrong.

**CRDTs via Automerge or Yjs.** Rejected as disproportionate. Worth
revisiting if highlights and annotations arrive, where concurrent edits to
overlapping ranges are a real merge problem rather than a scalar comparison.

**Server-assigned timestamps only, no client clock.** Rejected: it would make
ordering depend on network delivery order, so a write made first offline could
be ordered after one made later on a connected device.
