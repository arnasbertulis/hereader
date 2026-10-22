import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:rsvp_engine/rsvp_engine.dart';
import 'package:test/test.dart';

Duration _ms(int n) => Duration(milliseconds: n);

/// At 300 wpm a token holds 200ms.
List<Token> _tokens(int count, {PauseAfter last = PauseAfter.none}) => [
  for (var i = 0; i < count; i++)
    Token(
      text: 'w$i',
      charOffset: i * 3,
      pauseAfter: i == count - 1 ? last : PauseAfter.none,
    ),
];

ReadingProfile _profile({String id = 'test'}) => ReadingProfile(
  id: id,
  name: 'Test',
  rewindWords: 0,
  pacing: const PacingConfig(kind: PacingModelKind.constant, baseWpm: 300),
);

/// A `clock` that reads [lateness] further ahead each time a timer fires,
/// which is what a late timer looks like from inside its callback.
///
/// `fakeAsync` fires every timer exactly on time, so without this a test
/// cannot see drift. The skew lives here, in the test: the session has no seam
/// for it.
class _LateClock {
  final FakeAsync async;
  final Duration lateness;
  final DateTime _epoch = DateTime.utc(2030);

  int _fired = 0;

  /// A one-off jump on top of the per-timer lateness: a suspended app.
  Duration slept = Duration.zero;

  _LateClock(this.async, this.lateness);

  DateTime _now() =>
      async.getClock(_epoch).now().add(lateness * _fired).add(slept);

  /// Run [body] with `clock` skewed and every timer created inside it counted
  /// as it fires.
  T run<T>(T Function() body) => runZoned(
    () => withClock(Clock(_now), body),
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) =>
          parent.createTimer(zone, duration, () {
            _fired++;
            callback();
          }),
    ),
  );
}

/// The virtual time at which each change of index was seen, in order.
List<Duration> _changes(FakeAsync async, PlaybackSession session) {
  final at = <Duration>[];
  var last = session.index;
  session.updates.listen((u) {
    if (u.index != last) {
      last = u.index;
      at.add(async.elapsed);
    }
  });
  return at;
}

void main() {
  group('timers that fire late', () {
    test('total elapsed time tracks the sum of the holds', () {
      fakeAsync((async) {
        // Ten 200ms holds: 2000ms. At 50ms late per timer and no
        // compensation the run would end at 2500ms.
        _LateClock(async, _ms(50)).run(() {
          final s = PlaybackSession(tokens: _tokens(10), profile: _profile());
          final start = clock.now();
          DateTime? end;
          s.updates.listen((u) {
            if (u.state == PlaybackState.finished) end = clock.now();
          });
          s.play();
          async.elapse(const Duration(seconds: 5));

          expect(s.state, PlaybackState.finished);
          expect(end!.difference(start).inMilliseconds, closeTo(2000, 200));
          s.dispose();
        });
      });
    });

    test('a gap after a word is timed against the same schedule', () {
      fakeAsync((async) {
        // Five 200ms holds and a 220ms sentence pause: 1220ms. Six timers at
        // 50ms late would end at 1520ms.
        _LateClock(async, _ms(50)).run(() {
          final s = PlaybackSession(
            tokens: _tokens(5, last: PauseAfter.sentence),
            profile: _profile(),
          );
          final start = clock.now();
          DateTime? end;
          s.updates.listen((u) {
            if (u.state == PlaybackState.finished) end = clock.now();
          });
          s.play();
          async.elapse(const Duration(seconds: 5));

          expect(s.state, PlaybackState.finished);
          expect(end!.difference(start).inMilliseconds, closeTo(1220, 200));
          s.dispose();
        });
      });
    });

    test('no hold is shortened by more than half its length', () {
      fakeAsync((async) {
        // 150ms late against a 200ms hold would shorten it to 50ms.
        _LateClock(async, _ms(150)).run(() {
          final s = PlaybackSession(tokens: _tokens(10), profile: _profile());
          final at = _changes(async, s);
          s.play();
          async.elapse(const Duration(seconds: 5));

          expect(at, hasLength(9));
          var previous = Duration.zero;
          for (final t in at) {
            expect(t - previous, greaterThanOrEqualTo(_ms(100)));
            previous = t;
          }
          s.dispose();
        });
      });
    });

    test('a stall of more than a second re-anchors instead of flashing', () {
      fakeAsync((async) {
        final skew = _LateClock(async, Duration.zero);
        skew.run(() {
          final s = PlaybackSession(tokens: _tokens(10), profile: _profile());
          final at = _changes(async, s);
          s.play();
          async.elapse(_ms(100));
          // The laptop sleeps for a minute inside the first hold.
          skew.slept = const Duration(minutes: 1);
          async.elapse(const Duration(seconds: 5));

          // Without the guard the next nine holds would race at 100ms each.
          expect(at.first, _ms(200));
          var previous = Duration.zero;
          for (final t in at) {
            expect(t - previous, _ms(200));
            previous = t;
          }
          s.dispose();
        });
      });
    });

    test('a clock stepped backwards never stretches a hold', () {
      fakeAsync((async) {
        final skew = _LateClock(async, Duration.zero);
        skew.run(() {
          final s = PlaybackSession(tokens: _tokens(10), profile: _profile());
          final at = _changes(async, s);
          s.play();
          async.elapse(_ms(100));
          // An NTP correction moves the wall clock back ten seconds.
          skew.slept = const Duration(seconds: -10);
          async.elapse(const Duration(seconds: 5));

          expect(at, hasLength(9));
          var previous = Duration.zero;
          for (final t in at) {
            expect(t - previous, _ms(200));
            previous = t;
          }
          s.dispose();
        });
      });
    });
  });

  group('re-anchoring', () {
    test('pause then resume neither catches up nor loses time', () {
      fakeAsync((async) {
        final s = PlaybackSession(tokens: _tokens(10), profile: _profile());
        final at = _changes(async, s);
        s.play();
        async.elapse(_ms(150));
        s.pause();
        async.elapse(const Duration(seconds: 5));
        s.play();
        async.elapse(const Duration(seconds: 1));

        // 50ms were left of the first hold when it paused. Then full holds.
        expect(at.take(3), [
          const Duration(milliseconds: 5200),
          const Duration(milliseconds: 5400),
          const Duration(milliseconds: 5600),
        ]);
        s.dispose();
      });
    });

    // Each of these happens 10ms after the first timer, which has fired 50ms
    // late. A schedule that survived the move would shorten the next hold; a
    // move starts a full one.
    void movesReanchor(String name, void Function(PlaybackSession) move) {
      test('$name starts a full hold', () {
        fakeAsync((async) {
          _LateClock(async, _ms(50)).run(() {
            final s = PlaybackSession(tokens: _tokens(10), profile: _profile());
            s.play();
            async.elapse(_ms(210));
            move(s);
            final moved = s.index;

            async.elapse(_ms(199));
            expect(s.index, moved);
            async.elapse(_ms(1));
            expect(s.index, moved + 1);
            s.dispose();
          });
        });
      });
    }

    movesReanchor('a step', (s) => s.advance());
    movesReanchor('a seek', (s) => s.seekToIndex(6));
    movesReanchor('a profile change', (s) => s.profile = _profile(id: 'other'));
  });
}
