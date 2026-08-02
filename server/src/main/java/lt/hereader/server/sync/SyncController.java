package lt.hereader.server.sync;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/// The sync API.
///
/// Every method takes the user id from the validated token, never from the
/// request. Accepting an owner from the body would let any account write into
/// any other account's stream.
@RestController
@RequestMapping("/sync")
class SyncController {

    private final SyncService sync;

    SyncController(SyncService sync) {
        this.sync = sync;
    }

    /// Accepts a batch from a device's outbox.
    ///
    /// Safe to retry: events carry idempotency keys, and one already seen is
    /// reported back rather than applied twice.
    @PostMapping("/events")
    SyncDtos.PushResponse push(
            @AuthenticationPrincipal UUID userId,
            @Valid @RequestBody SyncDtos.PushRequest request) {

        return sync.push(userId, request);
    }

    /// Everything after a sequence number.
    ///
    /// A client stores the last sequence it saw and asks from there, so a
    /// device that has been away for a month makes the same request as one
    /// away for a minute.
    @GetMapping("/events")
    SyncDtos.PullResponse pull(
            @AuthenticationPrincipal UUID userId,
            @RequestParam(defaultValue = "0") long since,
            @RequestParam(defaultValue = "200") int limit) {

        if (since < 0) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "since cannot be negative.");
        }
        return sync.pull(userId, since, limit);
    }

    /// Reading positions that diverged enough to need the reader's decision.
    @GetMapping("/conflicts")
    List<SyncDtos.PositionConflict> conflicts(
            @AuthenticationPrincipal UUID userId) {

        return sync.conflicts(userId);
    }

    record ResolveBody(Map<String, Object> chosen, String hlc, String deviceId) {}

    /// Settles a divergence with the position the reader picked.
    @PostMapping("/conflicts/{id}/resolve")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void resolve(
            @AuthenticationPrincipal UUID userId,
            @PathVariable long id,
            @RequestBody ResolveBody body) {

        if (body.chosen() == null || body.hlc() == null
                || body.deviceId() == null) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "chosen, hlc and deviceId are all required.");
        }

        sync.resolveConflict(
                userId, id, body.chosen(), body.hlc(), body.deviceId());
    }
}
