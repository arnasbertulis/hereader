package lt.hereader.server.sync;

import java.time.Duration;
import java.time.Instant;
import java.util.regex.Pattern;

/// A hybrid logical clock stamp.
///
/// Wall clocks disagree across devices, so ordering by timestamp alone can
/// pick the older write. Pure logical counters order correctly but lose any
/// relation to real time. An HLC is both: a millisecond, a counter for writes
/// landing in the same millisecond, and a device id to break remaining ties.
///
/// The fixed-width format means lexicographic string comparison gives the
/// same answer as comparing the parts, so ordering works in SQL without
/// parsing.
///
/// Format: {millis:013d}-{counter:05d}-{deviceId}
public record Hlc(long millis, int counter, String deviceId)
        implements Comparable<Hlc> {

    private static final Pattern FORMAT =
            Pattern.compile("^(\\d{13})-(\\d{5})-([A-Za-z0-9_-]{1,64})$");

    /// How far ahead of the server a client stamp may be.
    ///
    /// Clients supply their own stamps, so a skewed or hostile device could
    /// claim a time far in the future and win every comparison from then on,
    /// permanently. Anything beyond this is rejected rather than clamped:
    /// silently rewriting a client's stamp would break its own local
    /// ordering.
    public static final Duration MAX_DRIFT_AHEAD = Duration.ofMinutes(5);

    public static Hlc parse(String value) {
        if (value == null) {
            throw new IllegalArgumentException("Missing clock stamp.");
        }

        var matcher = FORMAT.matcher(value);
        if (!matcher.matches()) {
            throw new IllegalArgumentException(
                    "Malformed clock stamp: " + value);
        }

        return new Hlc(
                Long.parseLong(matcher.group(1)),
                Integer.parseInt(matcher.group(2)),
                matcher.group(3));
    }

    /// True when this stamp claims a time the server considers impossible.
    ///
    /// Only the future is checked. A stamp from the past is ordinary: it
    /// means a device wrote while offline and is only now reporting it.
    public boolean isTooFarAhead(Instant now) {
        return millis > now.plus(MAX_DRIFT_AHEAD).toEpochMilli();
    }

    @Override
    public String toString() {
        return "%013d-%05d-%s".formatted(millis, counter, deviceId);
    }

    @Override
    public int compareTo(Hlc other) {
        // Same order the string comparison gives, spelled out so the
        // intent survives a format change.
        int byTime = Long.compare(millis, other.millis);
        if (byTime != 0) return byTime;

        int byCounter = Integer.compare(counter, other.counter);
        if (byCounter != 0) return byCounter;

        return deviceId.compareTo(other.deviceId);
    }
}
