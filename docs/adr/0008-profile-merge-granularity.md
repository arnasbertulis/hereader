# 0008. Profiles merge whole, at per-profile granularity

Date: 2026-08-09

## Status

Accepted.

## Context

ADR 0005 assigned reading profiles last-write-wins and moved on, because at
the time nothing could edit one. Profiles were selectable, not editable, so
the entity was never contested and the rule was never exercised: the sync
client stored inbound profile events nowhere and the `PROFILE` branch of its
apply loop was an explicit no-op.

A settings screen changes that. A profile is now something a reader creates,
renames, retunes and deletes, on any device, possibly while another device is
doing the same. The rule ADR 0005 stated in one line is now load-bearing and
deserves the reasoning it did not need before.

Reading positions already showed that one policy does not fit every entity, so
the question is which policy this one takes.

Three options.

**Whole-object last write wins.** The later write replaces the profile
entirely. Simplest, and discards the losing edit.

**Field-level merge.** Not a new conflict rule so much as a change of
granularity: if the entity key becomes `(profileId, fieldName)` and each event
says "profile X's fontSize is 24" rather than "profile X is this object", the
existing last-write-wins machinery merges concurrent edits to different fields
with no new code in the resolver.

**Ask the reader**, as reading positions do beyond the divergence threshold.

## Decision

### Whole-object last write wins

Profile fields are not independent. ADR 0003 makes this explicit:
`lengthScaleStrength`, `baseWpm` and `referenceLetterCount` are one coherent
tuning rather than three scalars, `chunkSize` interacts with
`PresentationMode`, and under `elicited` pacing every duration field is
meaningless. Merging field by field can therefore produce a configuration that
neither device chose and no reader ever looked at — a coherent "large type,
slow, reader-advances" profile crossed with a coherent "small type, fast,
timed" one, yielding something that is neither.

Whole-object replacement guarantees the surviving profile is one a person
deliberately assembled and saw. Losing one clean edit is better than keeping an
incoherent merge.

The failure also corrects itself cheaply, which is the other half of the
argument. A reading position resolved wrongly is invisible until the reader is
lost in the wrong chapter, and by then the right one may be unrecoverable. A
profile resolved wrongly is visible the moment settings opens, and redoing the
edit takes seconds. That asymmetry is exactly what justified different rules
per entity in ADR 0005, and it points the opposite way here.

A prompt was rejected for the same reason. Surfacing a divergence is worth it
when the reader knows something the system does not — which device they were
actually reading on. Asked which font size they meant, the honest answer is
"either, just pick one". A prompt there is interruption without information.

### Each profile is its own entity

The event's entity id is the profile id, not a single key covering all
settings. Editing one profile on a phone and a different one on a desktop then
never compares at all: different entities, no contest, both survive.

This costs nothing and removes most realistic concurrent-edit cases. What
remains is two devices editing *the same* profile while apart, which is rare
enough that discarding one side is acceptable. Without this granularity the
whole-object rule would be considerably harder to defend, because every edit
would contend with every other.

### Built-in presets are code and are never stored or synced

Presets live in `Presets.all` and are merged into the profile list at read
time. Nothing writes them to the database and no event carries one.

Each preset is tied to a specific finding in the evidence notes, so a preset
edited past recognition would carry a name that no longer describes it, with
no tested starting point left to return to. Editing one forks it into a copy
the reader owns. That also means a preset revised in a later release cannot
collide with a reader's modified version of the old one, since the two are
different entities with different ids.

### `isBuiltIn` is derived from the id namespace, not stored

Any id under `builtin.` is a preset; anything else is not. A stored boolean
would be a second source of truth for one fact, and — more importantly — a
value the wire could set. A profile arriving through sync claiming
`isBuiltIn: true` would render as one the reader can neither edit nor delete,
and could shadow a preset the app guarantees is always available. Deriving it
makes the claim unforgeable, and the repository refuses any inbound profile
whose id sits in that namespace.

### The active profile pointer is device-local

Which profiles exist syncs. Which one is in use does not.

A phone read outdoors and a desktop in a dim room can reasonably want
different profiles active, and a shared pointer would have each device pulling
the other's choice out from under it — a change that looks like the app
overriding a deliberate decision rather than syncing anything.

A pointer at a profile deleted elsewhere resolves to a named preset, not to
whatever happens to be first in the list. A positional fallback shifts as
profiles come and go, which reads as the app reassigning settings at random.
The dead pointer is cleared when it fails to resolve rather than re-tried on
every open.

`setPreference` gained an explicit `sync` parameter defaulting to false as
part of this. It had never enqueued anything, so every preference was
device-local by omission rather than decision, and completing preference sync
later would have made the active pointer start travelling without anyone
choosing that.

### A deletion is recorded on the event, not only on the resolved state

Deleting a profile writes a tombstone rather than removing the row, on the
client and on the service. An absent row and a row deleted a second ago are
indistinguishable, so without a stamp to lose against, any device that was
offline during the deletion would push its stale create and resurrect the
profile.

The service keeps both an append-only log and a resolved value per entity.
Clients pull the log. `entity_state` had carried a `deleted` flag since V2 and
resolution set it correctly, but `sync_events` had no such column and the pull
query filled the field with a constant `false`. A deletion would therefore have
arrived on every other device as an ordinary write carrying the profile's last
payload and the deletion's stamp — the highest stamp in play — and each would
have written the profile back as live. The deleting device keeps its own
tombstone, since it skips echoes of its own writes, so the two would disagree
permanently with nothing logged anywhere.

This was found by reading the wire contract end to end before attempting a
cross-device test. Neither test suite could have caught it: the Dart tests run
against a fake service, and the Java tests had never exercised a deletion
because no client had ever sent one.

## Consequences

Two devices editing the same profile while apart lose one set of edits. This is
the deliberate cost and it is real. It is listed in the README's known
limitations rather than described as a merge.

Improving a preset is a code change and a release, not a migration. Readers
who forked the old one keep their fork untouched, which is correct and also
means they do not receive the improvement.

Client schema moves to version 4, adding `deleted` to `stored_profiles` and to
`outbox_events`. Service schema moves to V3, adding `deleted` to
`sync_events`. All three default to false, which is the correct backfill and
not merely a convenient one: every row already on disk predates any client
that could produce a deletion.

Profile events are small and infrequent, so the log growth this adds is
negligible against position events.

The divergence machinery built for reading positions is not reused here and
`entity_state`'s conflict path never fires for profiles. That asymmetry is
intentional and is the substance of this document.

Preference sync remains inbound-only: the client applies preferences arriving
from other devices and never sends its own. ADR 0005 lists preferences as a
synced entity, so the document currently describes more than the code does.
Noted here because this ADR touched the same method and did not fix it.

## Verification

Verified across two real devices against the live service, not only against
the fake: a profile created on Windows appeared on the web client, an edit made
on web replaced it on Windows, a deletion on Windows removed it from web, and a
profile edited on a device that was offline did not come back after a newer
deletion elsewhere had already been applied.

The last of those is the case the whole tombstone design exists for, and the
one that would have failed silently before the service change above.

## Alternatives considered

**Field-level merge via `(profileId, fieldName)` entity keys.** Rejected. It
needs no new resolver code, which makes it tempting, but it can produce a
configuration neither device chose, and it makes creation and deletion awkward:
a new profile becomes many events, a deletion becomes a tombstone per field,
and a partially arrived profile renders as something nobody configured. Worth
revisiting only if profiles grow fields that are genuinely independent.

**Prompting the reader, as reading positions do.** Rejected. A prompt is
justified when the reader has information the system lacks. For a font size
they do not, so it is interruption without information.

**Syncing the active profile pointer.** Rejected, above.

**Storing presets as ordinary rows seeded on first run.** Rejected: it would
put presets into the sync stream, let one device's edit of a preset reach
another, and turn every future preset revision into a data migration with no
way to tell a reader's changes from the shipped defaults.
