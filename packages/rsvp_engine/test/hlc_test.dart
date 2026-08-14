import 'package:rsvp_engine/rsvp_engine.dart';
import 'package:test/test.dart';

/// A clock the test drives, so nothing sleeps and time can move backwards.
class _FakeClock {
  DateTime _now = DateTime.fromMillisecondsSinceEpoch(1785700000000);

  DateTime call() => _now;

  void advance(int millis) => _now = _now.add(Duration(milliseconds: millis));

  void rewind(int millis) =>
      _now = _now.subtract(Duration(milliseconds: millis));
}

void main() {
  group('HlcStamp format', () {
    test('pads to the widths the server expects', () {
      const stamp = HlcStamp(millis: 1, counter: 2, deviceId: 'laptop');

      // Fixed width is what makes string comparison agree with numeric
      // comparison, which is how the server orders without parsing.
      expect(stamp.toString(), '0000000000001-00002-laptop');
    });

    test('round trips through its string form', () {
      const original = HlcStamp(
        millis: 1785700000000,
        counter: 42,
        deviceId: 'phone-1',
      );

      expect(HlcStamp.parse(original.toString()), original);
    });

    test('rejects malformed stamps', () {
      expect(() => HlcStamp.parse('nonsense'), throwsFormatException);
      expect(() => HlcStamp.parse('123-00000-laptop'), throwsFormatException);
      expect(
        () => HlcStamp.parse('1785700000000-00000'),
        throwsFormatException,
      );
      expect(
        () => HlcStamp.parse("1785700000000-00000-'; drop table"),
        throwsFormatException,
      );
    });

    test('tryParse returns null rather than throwing', () {
      expect(HlcStamp.tryParse('nonsense'), isNull);
      expect(HlcStamp.tryParse('0000000000001-00002-a'), isNotNull);
    });
  });

  group('HlcStamp ordering', () {
    test('orders by time first', () {
      expect(
        const HlcStamp(millis: 2000, counter: 0, deviceId: 'a') >
            const HlcStamp(millis: 1000, counter: 99, deviceId: 'z'),
        isTrue,
      );
    });

    test('orders by counter within a millisecond', () {
      expect(
        const HlcStamp(millis: 1000, counter: 2, deviceId: 'a') >
            const HlcStamp(millis: 1000, counter: 1, deviceId: 'z'),
        isTrue,
      );
    });

    test('breaks remaining ties by device', () {
      // Arbitrary but deterministic: two devices writing in the same
      // millisecond must resolve the same way everywhere.
      expect(
        const HlcStamp(millis: 1000, counter: 0, deviceId: 'b') >
            const HlcStamp(millis: 1000, counter: 0, deviceId: 'a'),
        isTrue,
      );
    });

    test('string order matches comparable order', () {
      // The property the server depends on. If this ever fails, ordering in
      // SQL and ordering in the app have silently diverged.
      final stamps = [
        const HlcStamp(millis: 1785700000000, counter: 0, deviceId: 'phone'),
        const HlcStamp(millis: 1785699999999, counter: 9, deviceId: 'laptop'),
        const HlcStamp(millis: 1785700000000, counter: 1, deviceId: 'laptop'),
        const HlcStamp(millis: 1785700000000, counter: 0, deviceId: 'laptop'),
        const HlcStamp(millis: 1000, counter: 0, deviceId: 'tablet'),
      ];

      final byComparable = [...stamps]..sort();
      final byString = [...stamps]
        ..sort((a, b) => a.toString().compareTo(b.toString()));

      expect(byString, equals(byComparable));
    });
  });

  group('issuing', () {
    late _FakeClock clock;
    late HybridLogicalClock hlc;

    setUp(() {
      clock = _FakeClock();
      hlc = HybridLogicalClock(deviceId: 'laptop', now: clock.call);
    });

    test('uses the wall clock when time has moved', () {
      clock.advance(5);
      final stamp = hlc.issue();

      expect(stamp.millis, 1785700000005);
      expect(stamp.counter, 0);
      expect(stamp.deviceId, 'laptop');
    });

    test('increments the counter within one millisecond', () {
      final first = hlc.issue();
      final second = hlc.issue();
      final third = hlc.issue();

      expect(first.millis, second.millis);
      expect([first.counter, second.counter, third.counter], [0, 1, 2]);
    });

    test('resets the counter when the millisecond advances', () {
      hlc.issue();
      hlc.issue();

      clock.advance(1);
      expect(hlc.issue().counter, 0);
    });

    test('never issues a stamp that loses to an earlier one', () {
      final stamps = <HlcStamp>[];

      for (var i = 0; i < 20; i++) {
        stamps.add(hlc.issue());
        if (i % 3 == 0) clock.advance(1);
      }

      for (var i = 1; i < stamps.length; i++) {
        expect(
          stamps[i] > stamps[i - 1],
          isTrue,
          reason: 'stamp $i did not advance',
        );
      }
    });

    test('survives the system clock going backwards', () {
      final before = hlc.issue();

      // A correction, a timezone bug, a manual change: all real.
      clock.rewind(60000);
      final after = hlc.issue();

      expect(after > before, isTrue);
      expect(
        after.millis,
        before.millis,
        reason: 'keeps the millisecond it already used',
      );
      expect(after.counter, before.counter + 1);
    });
  });

  group('observing remote stamps', () {
    late _FakeClock clock;
    late HybridLogicalClock hlc;

    setUp(() {
      clock = _FakeClock();
      hlc = HybridLogicalClock(deviceId: 'laptop', now: clock.call);
    });

    test('the next stamp sorts after one seen from another device', () {
      const remote = HlcStamp(
        millis: 1785700005000,
        counter: 3,
        deviceId: 'phone',
      );

      hlc.observe(remote);
      final mine = hlc.issue();

      expect(mine > remote, isTrue);
    });

    test('a remote stamp from the past does not drag this clock back', () {
      clock.advance(10);
      final before = hlc.issue();

      hlc.observe(
        const HlcStamp(millis: 1000, counter: 0, deviceId: 'ancient'),
      );

      expect(hlc.issue() > before, isTrue);
    });

    test('two clocks converge through each other', () {
      final phoneClock = _FakeClock()..advance(3000);
      final phone = HybridLogicalClock(deviceId: 'phone', now: phoneClock.call);

      // Laptop writes, phone sees it and writes, laptop sees that.
      final a = hlc.issue();
      phone.observe(a);
      final b = phone.issue();
      hlc.observe(b);
      final c = hlc.issue();

      expect(b > a, isTrue);
      expect(c > b, isTrue);
    });
  });

  group('restoring after a restart', () {
    test('does not reissue stamps that already exist', () {
      final clock = _FakeClock();
      final hlc = HybridLogicalClock(deviceId: 'laptop', now: clock.call);

      clock.advance(100);
      final beforeRestart = hlc.issue();

      // Restarted, and the system clock has since been corrected backwards.
      final laterClock = _FakeClock();
      final restored = HybridLogicalClock(
        deviceId: 'laptop',
        now: laterClock.call,
      )..restoreFrom(beforeRestart);

      expect(restored.issue() > beforeRestart, isTrue);
    });

    test('lastIssued is null until something is issued', () {
      final hlc = HybridLogicalClock(deviceId: 'laptop');

      expect(hlc.lastIssued, isNull);
      hlc.issue();
      expect(hlc.lastIssued, isNotNull);
    });
  });

  group('device ids', () {
    test('rejects ids the server would refuse', () {
      // The server's pattern is the contract; failing here beats failing on
      // every push with a 400.
      expect(() => HybridLogicalClock(deviceId: ''), throwsArgumentError);
      expect(
        () => HybridLogicalClock(deviceId: 'has spaces'),
        throwsArgumentError,
      );
      expect(() => HybridLogicalClock(deviceId: 'a' * 65), throwsArgumentError);
    });

    test('accepts letters, digits, underscore and hyphen', () {
      expect(() => HybridLogicalClock(deviceId: 'laptop-1_A'), returnsNormally);
    });
  });
}
