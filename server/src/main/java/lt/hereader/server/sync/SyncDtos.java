package lt.hereader.server.sync;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;

import java.util.List;
import java.util.Map;

/// Wire types for the sync API.
///
/// Deliberately separate from anything stored: a change to the database shape
/// should not silently change what clients see.
public final class SyncDtos {

    private SyncDtos() {}

    /// What a client knows how to sync.
    ///
    /// A closed set rather than a free string, so an unknown type is rejected
    /// at the edge instead of being stored and confusing a later reader.
    public enum EntityType {
        POSITION,
        PROFILE,
        PREFERENCE,
        BOOKMARK,
        BOOK_METADATA
    }

    public record PushEvent(
            @NotBlank @Size(max = 200) String idempotencyKey,
            EntityType entityType,
            @NotBlank @Size(max = 200) String entityId,
            /// Shape depends on entityType. Size-capped in the service:
            /// nothing here should be large, and a client that sends
            /// megabytes is either broken or hostile.
            Map<String, Object> payload,
            @NotBlank String hlc,
            /// True when this event deletes the entity. The row survives as
            /// a tombstone so the deletion reaches devices that were offline.
            boolean deleted) {}

    public record PushRequest(
            @NotBlank @Size(max = 64) String deviceId,
            @NotEmpty @Size(max = 500) List<@Valid PushEvent> events) {}

    public record PushResponse(
            /// Highest sequence number now assigned to this user. A client
            /// stores it and pulls from there next time.
            long lastSeq,
            int accepted,
            /// Keys the server had already seen. Not an error: it means an
            /// earlier response was lost and the client retried correctly.
            List<String> duplicates,
            /// Positions that diverged enough to need the reader's decision.
            List<PositionConflict> conflicts) {}

    public record PulledEvent(
            long seq,
            EntityType entityType,
            String entityId,
            Map<String, Object> payload,
            String hlc,
            String deviceId,
            boolean deleted) {}

    public record PullResponse(
            List<PulledEvent> events,
            long lastSeq,
            /// True when more events remain past this batch.
            boolean hasMore) {}

    public record PositionConflict(
            long id,
            String bookId,
            Map<String, Object> ours,
            Map<String, Object> theirs) {}

    public record ResolveConflictRequest(
            /// Which side the reader chose. The other is discarded.
            @NotBlank String choice) {}
}
