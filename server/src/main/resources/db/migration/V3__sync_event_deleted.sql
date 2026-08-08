-- The event log could not say that an event was a deletion.
--
-- entity_state has carried a deleted flag since V2, so resolution was correct,
-- but sync_events did not, and the pull query filled the field with a constant
-- false. A deletion therefore reached other devices as an ordinary write
-- carrying the entity's last known payload, and any device pulling it wrote
-- the entity back as live. The deleting device kept its own tombstone, since
-- it skips the echo of its own writes, so the two disagreed permanently with
-- no error raised anywhere.
--
-- ADR 0005 requires deletions to travel as tombstones. The log is the source
-- of truth, so the flag has to live here and not only in the resolved state.
--
-- Defaulting to false is the correct backfill rather than a convenience: no
-- client had ever set the field, so every event already in the log is a write.
alter table sync_events
    add column deleted boolean not null default false;
