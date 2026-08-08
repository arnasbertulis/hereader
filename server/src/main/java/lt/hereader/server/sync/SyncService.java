package lt.hereader.server.sync;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/// Applies pushed events and resolves conflicts.
///
/// Resolution rules differ by entity type, which is the substantive decision
/// here. See ADR 0005.
@Service
public class SyncService {

    /// Token distance beyond which two reading positions are treated as a
    /// real divergence rather than the same place.
    ///
    /// Roughly two minutes of reading. Below it, the reader would not notice
    /// which side won; above it, they read on both devices and picking one
    /// silently would drop them in the wrong part of the book.
    static final int POSITION_DIVERGENCE_TOKENS = 500;

    /// Cap on a single event's payload once encoded. Nothing synced here is
    /// large, so anything past this is a broken client or a hostile one.
    private static final int MAX_PAYLOAD_CHARS = 8_192;

    private static final int MAX_PULL_BATCH = 500;

    private final SyncRepository repository;

    SyncService(SyncRepository repository) {
        this.repository = repository;
    }

    /// Accepts a batch of events from one device.
    ///
    /// One transaction for the batch: a partially applied push would leave
    /// the client unable to tell what to resend, and its outbox would either
    /// duplicate work or drop it.
    @Transactional
    public SyncDtos.PushResponse push(UUID userId, SyncDtos.PushRequest request) {
        var now = Instant.now();

        for (var event : request.events()) {
            validate(event, now);
        }

        // Claimed once for the batch rather than per event, so a large push
        // takes one lock rather than many.
        long lastSeq = repository.claimSequenceNumbers(
                userId, request.events().size());
        long seq = lastSeq - request.events().size() + 1;

        var duplicates = new ArrayList<String>();

        for (var event : request.events()) {
            boolean appended = repository.appendEvent(
                    userId,
                    seq,
                    event.idempotencyKey(),
                    event.entityType().name(),
                    event.entityId(),
                    event.payload(),
                    event.hlc(),
                    request.deviceId(),
                    // Stored on the event, not only on the resolved state.
                    // A pulling device reads the log, so a deletion recorded
                    // only in entity_state would arrive elsewhere as an
                    // ordinary write and undo itself.
                    event.deleted());

            if (!appended) {
                // Already seen: an earlier response was lost and the client
                // retried. The event is already reflected in state.
                duplicates.add(event.idempotencyKey());
                continue;
            }

            resolve(userId, event, request.deviceId());
            seq++;
        }

        return new SyncDtos.PushResponse(
                lastSeq,
                request.events().size() - duplicates.size(),
                duplicates,
                repository.unresolvedConflicts(userId));
    }

    public SyncDtos.PullResponse pull(UUID userId, long since, int limit) {
        int capped = Math.min(Math.max(limit, 1), MAX_PULL_BATCH);

        // The repository fetches one extra so more-remaining is known
        // without a second query.
        var fetched = repository.eventsSince(userId, since, capped);
        boolean hasMore = fetched.size() > capped;

        var events = hasMore ? fetched.subList(0, capped) : fetched;

        return new SyncDtos.PullResponse(
                events,
                repository.lastSeq(userId),
                hasMore);
    }

    public List<SyncDtos.PositionConflict> conflicts(UUID userId) {
        return repository.unresolvedConflicts(userId);
    }

    /// Settles a divergence with the reader's choice.
    ///
    /// The chosen position is written as ordinary state with a fresh stamp,
    /// so it wins over both candidates on every device.
    @Transactional
    public void resolveConflict(
            UUID userId,
            long conflictId,
            Map<String, Object> chosen,
            String hlc,
            String deviceId) {

        var conflict = repository.unresolvedConflicts(userId).stream()
                .filter(c -> c.id() == conflictId)
                .findFirst()
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "No such unresolved conflict."));

        repository.upsertState(
                userId,
                SyncDtos.EntityType.POSITION.name(),
                conflict.bookId(),
                chosen,
                hlc,
                deviceId,
                false);

        repository.resolveConflict(userId, conflictId);
    }

    // -- resolution ----------------------------------------------------

    private void resolve(
            UUID userId, SyncDtos.PushEvent event, String deviceId) {

        var existing = repository.currentState(
                userId, event.entityType().name(), event.entityId());

        // Nothing to reconcile against.
        if (existing.isEmpty()) {
            repository.upsertState(
                    userId, event.entityType().name(), event.entityId(),
                    event.payload(), event.hlc(), deviceId, event.deleted());
            return;
        }

        var current = existing.get();
        var incoming = Hlc.parse(event.hlc());
        var stored = Hlc.parse(current.hlc());

        // An older write arriving late loses, whatever the entity.
        if (incoming.compareTo(stored) <= 0) {
            return;
        }

        if (event.entityType() == SyncDtos.EntityType.POSITION
                && !event.deleted()
                && !current.deleted()) {
            reconcilePosition(userId, event, deviceId, current);
            return;
        }

        // Everything else takes last write wins, deletions included: the row
        // survives as a tombstone so the deletion reaches devices that were
        // offline when it happened.
        repository.upsertState(
                userId, event.entityType().name(), event.entityId(),
                event.payload(), event.hlc(), deviceId, event.deleted());
    }

    /// Reading positions are the one case where silently picking a winner is
    /// wrong often enough to matter.
    ///
    /// The newer write still wins, so a reader who continues on one device is
    /// never held back. What changes is that a large gap is also recorded as
    /// a conflict, so the app can ask which position they meant.
    private void reconcilePosition(
            UUID userId,
            SyncDtos.PushEvent event,
            String deviceId,
            SyncRepository.StoredState current) {

        repository.upsertState(
                userId, event.entityType().name(), event.entityId(),
                event.payload(), event.hlc(), deviceId, false);

        var incomingIndex = tokenIndex(event.payload());
        var storedIndex = tokenIndex(current.payload());

        // Without hints from both sides there is no distance to judge, so
        // last write wins is all that can be done.
        if (incomingIndex == null || storedIndex == null) {
            return;
        }

        if (Math.abs(incomingIndex - storedIndex) < POSITION_DIVERGENCE_TOKENS) {
            return;
        }

        // Same device reading on: not a divergence, just progress.
        if (deviceId.equals(current.deviceId())) {
            return;
        }

        repository.recordConflict(
                userId, event.entityId(), current.payload(), event.payload());
    }

    /// Client-supplied hint for how far into the book a position is.
    ///
    /// The server cannot verify it, and does not need to: nothing
    /// security-related depends on it. A wrong value causes a prompt that was
    /// not needed, or misses one that was. The locator remains authoritative.
    private static Integer tokenIndex(Map<String, Object> payload) {
        var value = payload.get("tokenIndex");
        return value instanceof Number number ? number.intValue() : null;
    }

    // -- validation ----------------------------------------------------

    private void validate(SyncDtos.PushEvent event, Instant now) {
        final Hlc hlc;
        try {
            hlc = Hlc.parse(event.hlc());
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, e.getMessage());
        }

        // Rejected rather than clamped: rewriting a client's stamp would
        // break its own local ordering, since it stored one value and the
        // server kept another.
        if (hlc.isTooFarAhead(now)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Clock stamp is too far ahead of server time. "
                            + "Check this device's clock.");
        }

        if (event.payload() == null) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Event payload is missing.");
        }

        if (event.payload().toString().length() > MAX_PAYLOAD_CHARS) {
            throw new ResponseStatusException(
                    HttpStatus.PAYLOAD_TOO_LARGE,
                    "Event payload is too large.");
        }
    }
}
