package lt.hereader.server.sync;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class HlcTest {

    private static Hlc hlc(long millis, int counter, String device) {
        return new Hlc(millis, counter, device);
    }

    @Test
    void roundTripsThroughItsStringForm() {
        var original = hlc(1785700000000L, 42, "laptop");

        assertThat(Hlc.parse(original.toString())).isEqualTo(original);
    }

    @Test
    void padsToAFixedWidth() {
        // Fixed width is what makes lexicographic comparison agree with
        // numeric comparison, which is what lets the database order by the
        // string without parsing it.
        assertThat(hlc(1L, 2, "d").toString()).isEqualTo("0000000000001-00002-d");
    }

    @Test
    void ordersByTimeFirst() {
        assertThat(hlc(2000, 0, "a")).isGreaterThan(hlc(1000, 99, "z"));
    }

    @Test
    void ordersByCounterWithinAMillisecond() {
        assertThat(hlc(1000, 2, "a")).isGreaterThan(hlc(1000, 1, "z"));
    }

    @Test
    void breaksRemainingTiesByDevice() {
        // Arbitrary but deterministic: two devices writing in the same
        // millisecond must resolve the same way everywhere.
        assertThat(hlc(1000, 0, "b")).isGreaterThan(hlc(1000, 0, "a"));
    }

    @Test
    void stringOrderMatchesComparableOrder() {
        var stamps = new ArrayList<>(List.of(
                hlc(1785700000000L, 0, "phone"),
                hlc(1785699999999L, 9, "laptop"),
                hlc(1785700000000L, 1, "laptop"),
                hlc(1785700000000L, 0, "laptop"),
                hlc(1000L, 0, "tablet")));

        var byComparable = new ArrayList<>(stamps);
        byComparable.sort(Hlc::compareTo);

        var byString = new ArrayList<>(stamps);
        byString.sort((a, b) -> a.toString().compareTo(b.toString()));

        assertThat(byString).isEqualTo(byComparable);
    }

    @Test
    void rejectsStampsFromTheFuture() {
        var now = Instant.now();
        var farAhead = hlc(now.toEpochMilli() + 600_000, 0, "skewed");

        assertThat(farAhead.isTooFarAhead(now)).isTrue();
    }

    @Test
    void toleratesSmallClockSkew() {
        // Devices are never perfectly in step. A few seconds ahead is
        // ordinary, not an attack.
        var now = Instant.now();
        var slightlyAhead = hlc(now.toEpochMilli() + 30_000, 0, "phone");

        assertThat(slightlyAhead.isTooFarAhead(now)).isFalse();
    }

    @Test
    void acceptsStampsFromThePast() {
        // A device that wrote while offline reports an old stamp when it
        // reconnects. That is the normal case, not an error.
        var now = Instant.now();
        var lastWeek = hlc(now.toEpochMilli() - 604_800_000L, 0, "laptop");

        assertThat(lastWeek.isTooFarAhead(now)).isFalse();
    }

    @Test
    void rejectsMalformedStamps() {
        assertThatThrownBy(() -> Hlc.parse("not-a-stamp"))
                .isInstanceOf(IllegalArgumentException.class);

        // Wrong widths, missing parts, and injection attempts in the device
        // id all fail the same way.
        assertThatThrownBy(() -> Hlc.parse("123-00000-laptop"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> Hlc.parse("1785700000000-00000"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> Hlc.parse("1785700000000-00000-'; drop table"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> Hlc.parse(null))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
