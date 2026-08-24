-- Three schema mistakes from V1/V2, found by reading what actually reads
-- these tables rather than assuming from the table definitions alone.

-- 1. sync_events_user_seq duplicates the index Postgres already built for
-- `unique (user_id, seq)` at V1. Same columns, same order: one index
-- maintained twice on every insert into an append-only log, for no second
-- access pattern that needs it.
drop index sync_events_user_seq;

-- 2. entity_state_lookup indexes (user_id, entity_type, updated_at), but
-- every read of entity_state filters on (user_id, entity_type, entity_id) —
-- SyncRepository.currentState and the on-conflict target in
-- SyncRepository.upsertState both key on that triple, which is the primary
-- key from V2. Nothing anywhere orders or filters by updated_at.
drop index entity_state_lookup;

-- 3. `unique (user_id, book_id, resolved_at)` from V2 does not prevent what
-- SyncRepository.recordConflict is trying to prevent. Postgres treats NULLs
-- as distinct in a unique constraint by default, so any number of rows with
-- resolved_at is null pass it — exactly the "one unresolved conflict per
-- book" case recordConflict's `where not exists` guard exists to enforce.
-- That guard is a check-then-insert in one statement, but under read
-- committed two concurrent transactions can both see no row and both
-- insert, so the application-level check alone races.
--
-- Considered `unique nulls not distinct (user_id, book_id, resolved_at)`
-- instead of a partial index: it would close the race, but it also forbids
-- two rows resolved at the identical timestamp, which is not an invariant
-- anyone wants — it constrains the resolved case as a side effect of fixing
-- the unresolved one. A partial unique index constrains only the case that
-- is actually invariant: at most one unresolved conflict per (user_id,
-- book_id), and says nothing about resolved rows.
--
-- A pre-existing database may already hold duplicate unresolved rows the
-- old constraint let through — the deployed one is small and the race
-- window is narrow, but the migration must not be able to fail on main.
-- Keep the newest unresolved row per (user_id, book_id) and delete the
-- rest; (created_at, id) breaks ties deterministically since created_at
-- alone is not unique.
delete from position_conflicts pc
using position_conflicts newer
where pc.user_id = newer.user_id
  and pc.book_id = newer.book_id
  and pc.resolved_at is null
  and newer.resolved_at is null
  and (pc.created_at, pc.id) < (newer.created_at, newer.id);

alter table position_conflicts
    drop constraint position_conflicts_user_id_book_id_resolved_at_key;

create unique index position_conflicts_one_unresolved_per_book
    on position_conflicts (user_id, book_id)
    where resolved_at is null;
