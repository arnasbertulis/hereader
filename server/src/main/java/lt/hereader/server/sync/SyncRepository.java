package lt.hereader.server.sync;

import tools.jackson.core.JacksonException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import tools.jackson.databind.json.JsonMapper;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

@Repository
public class SyncRepository {

    /// The current resolved value for one entity, as stored.
    public record StoredState(
            Map<String, Object> payload,
            String hlc,
            String deviceId,
            boolean deleted) {}

    private final JdbcClient jdbc;
    private final JsonMapper json;

    SyncRepository(JdbcClient jdbc, JsonMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    /// Claims the next block of sequence numbers for a user.
    ///
    /// The update locks the row, so two devices pushing at once cannot be
    /// handed the same numbers. Returns the last number in the claimed
    /// block, so a caller assigning n events uses (result - n + 1) upward.
    public long claimSequenceNumbers(UUID userId, int count) {
        return jdbc.sql("""
                update user_sync_state
                set last_seq = last_seq + :count
                where user_id = :userId
                returning last_seq
                """)
                .param("userId", userId)
                .param("count", count)
                .query(Long.class)
                .single();
    }

    /// Appends an event.
    ///
    /// Returns false when the idempotency key has been seen before, which
    /// means an earlier response was lost and the client retried. Not an
    /// error: the correct response is to carry on.
    ///
    /// Relies on the unique constraint rather than a preceding select, so
    /// the guarantee holds under concurrent pushes instead of depending on
    /// a check and an insert staying together.
    ///
    /// [deleted] is stored on the event rather than only on the resolved
    /// state. The log is what a device pulls, so a deletion that is recorded
    /// only in entity_state reaches other devices as an ordinary write.
    public boolean appendEvent(
            UUID userId,
            long seq,
            String idempotencyKey,
            String entityType,
            String entityId,
            Map<String, Object> payload,
            String hlc,
            String deviceId,
            boolean deleted) {

        int rows = jdbc.sql("""
                insert into sync_events
                    (user_id, seq, idempotency_key, entity_type, entity_id,
                     payload, hlc, device_id, deleted)
                values
                    (:userId, :seq, :key, :type, :entityId,
                     cast(:payload as jsonb), :hlc, :deviceId, :deleted)
                on conflict (user_id, idempotency_key) do nothing
                """)
                .param("userId", userId)
                .param("seq", seq)
                .param("key", idempotencyKey)
                .param("type", entityType)
                .param("entityId", entityId)
                .param("payload", toJson(payload))
                .param("hlc", hlc)
                .param("deviceId", deviceId)
                .param("deleted", deleted)
                .update();

        return rows > 0;
    }

    public Optional<StoredState> currentState(
            UUID userId, String entityType, String entityId) {

        return jdbc.sql("""
                select payload, hlc, device_id, deleted
                from entity_state
                where user_id = :userId
                  and entity_type = :type
                  and entity_id = :entityId
                """)
                .param("userId", userId)
                .param("type", entityType)
                .param("entityId", entityId)
                .query((rs, _) -> new StoredState(
                        fromJson(rs.getString("payload")),
                        rs.getString("hlc"),
                        rs.getString("device_id"),
                        rs.getBoolean("deleted")))
                .optional();
    }

    /// Writes the resolved value for an entity.
    ///
    /// The where clause is the safety net: even if two requests race past
    /// the service's comparison, the older stamp cannot overwrite the newer
    /// one. HLC strings are fixed-width, so comparing them as text gives the
    /// same order as comparing the parts.
    public void upsertState(
            UUID userId,
            String entityType,
            String entityId,
            Map<String, Object> payload,
            String hlc,
            String deviceId,
            boolean deleted) {

        jdbc.sql("""
                insert into entity_state
                    (user_id, entity_type, entity_id, payload, hlc,
                     device_id, deleted, updated_at)
                values
                    (:userId, :type, :entityId, cast(:payload as jsonb),
                     :hlc, :deviceId, :deleted, now())
                on conflict (user_id, entity_type, entity_id) do update set
                    payload    = excluded.payload,
                    hlc        = excluded.hlc,
                    device_id  = excluded.device_id,
                    deleted    = excluded.deleted,
                    updated_at = now()
                where entity_state.hlc < excluded.hlc
                """)
                .param("userId", userId)
                .param("type", entityType)
                .param("entityId", entityId)
                .param("payload", toJson(payload))
                .param("hlc", hlc)
                .param("deviceId", deviceId)
                .param("deleted", deleted)
                .update();
    }

    /// Events after a sequence number, oldest first.
    ///
    /// Asks for one more than the caller wants, so the caller can tell
    /// whether more remain without a second count query.
    public List<SyncDtos.PulledEvent> eventsSince(
            UUID userId, long since, int limit) {

        return jdbc.sql("""
                select seq, entity_type, entity_id, payload, hlc, device_id,
                       deleted
                from sync_events
                where user_id = :userId and seq > :since
                order by seq
                limit :limit
                """)
                .param("userId", userId)
                .param("since", since)
                .param("limit", limit + 1)
                .query((rs, _) -> new SyncDtos.PulledEvent(
                        rs.getLong("seq"),
                        SyncDtos.EntityType.valueOf(rs.getString("entity_type")),
                        rs.getString("entity_id"),
                        fromJson(rs.getString("payload")),
                        rs.getString("hlc"),
                        rs.getString("device_id"),
                        rs.getBoolean("deleted")))
                .list();
    }

    public long lastSeq(UUID userId) {
        return jdbc.sql("""
                select last_seq from user_sync_state where user_id = :userId
                """)
                .param("userId", userId)
                .query(Long.class)
                .optional()
                .orElse(0L);
    }

    // -- position conflicts --------------------------------------------

    /// Records a divergence for the reader to settle.
    ///
    /// Does nothing when an unresolved conflict already exists for the book:
    /// asking twice about the same book would be worse than asking once.
    public void recordConflict(
            UUID userId,
            String bookId,
            Map<String, Object> ours,
            Map<String, Object> theirs) {

        jdbc.sql("""
                insert into position_conflicts (user_id, book_id, ours, theirs)
                select :userId, :bookId, cast(:ours as jsonb),
                       cast(:theirs as jsonb)
                where not exists (
                    select 1 from position_conflicts
                    where user_id = :userId
                      and book_id = :bookId
                      and resolved_at is null
                )
                """)
                .param("userId", userId)
                .param("bookId", bookId)
                .param("ours", toJson(ours))
                .param("theirs", toJson(theirs))
                .update();
    }

    public List<SyncDtos.PositionConflict> unresolvedConflicts(UUID userId) {
        return jdbc.sql("""
                select id, book_id, ours, theirs
                from position_conflicts
                where user_id = :userId and resolved_at is null
                order by created_at
                """)
                .param("userId", userId)
                .query((rs, _) -> new SyncDtos.PositionConflict(
                        rs.getLong("id"),
                        rs.getString("book_id"),
                        fromJson(rs.getString("ours")),
                        fromJson(rs.getString("theirs"))))
                .list();
    }

    public void resolveConflict(UUID userId, long conflictId) {
        jdbc.sql("""
                        update position_conflicts
                        set resolved_at = now()
                        where id = :id and user_id = :userId and resolved_at is null
                        """)
                .param("id", conflictId)
                .param("userId", userId)
                .update();
    }

    // -- json ----------------------------------------------------------

    private String toJson(Map<String, Object> value) {
        try {
            return json.writeValueAsString(value);
        } catch (JacksonException e) {
            throw new IllegalArgumentException("Payload is not encodable.", e);
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> fromJson(String value) {
        try {
            return json.readValue(value, Map.class);
        } catch (JacksonException e) {
            throw new IllegalStateException("Stored payload is corrupt.", e);
        }
    }
}
