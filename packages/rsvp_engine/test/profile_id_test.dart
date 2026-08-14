import 'package:rsvp_engine/rsvp_engine.dart';
import 'package:test/test.dart';

/// Coverage for [ReadingProfile.newId], moved here with the function itself.
///
/// These assertions previously lived in `app/test/profile_sync_test.dart`,
/// where they ran on the Dart VM only. That is precisely where they were
/// least useful: the bug this function already carries a comment about —
/// `nextInt(1 << 32)` becoming `nextInt(0)` under dart2js's 32-bit shift
/// semantics — throws on the web target and passes everywhere else.
///
/// Run under `dart test -p chrome`, the second group below fails on that
/// bug rather than shipping past it.
void main() {
  group('ReadingProfile.newId', () {
    test('never lands in the built-in namespace', () {
      for (var i = 0; i < 100; i++) {
        expect(
          ReadingProfile.newId(),
          isNot(startsWith(ReadingProfile.builtInIdPrefix)),
        );
      }
    });

    test('two ids issued in the same millisecond differ', () {
      final ids = {for (var i = 0; i < 100; i++) ReadingProfile.newId()};
      expect(ids, hasLength(100));
    });

    test('draws a full 32 bits of entropy', () {
      // The regression guard. Under dart2js `1 << 32` is 0, so the earlier
      // implementation called nextInt(0) and threw; a draw that silently
      // narrowed instead would show up here as a short or constant suffix.
      final suffixes = <String>{};

      for (var i = 0; i < 200; i++) {
        final parts = ReadingProfile.newId().split('.');
        expect(parts, hasLength(3));

        final suffix = parts[2];
        expect(suffix, hasLength(8));

        final value = int.parse(suffix, radix: 16);
        expect(value, greaterThanOrEqualTo(0));
        expect(value, lessThanOrEqualTo(0xFFFFFFFF));

        suffixes.add(suffix);
      }

      // 200 draws from 2^32 collide with probability around 5e-6. A draw
      // narrowed to 16 bits would collide here almost every run.
      expect(suffixes, hasLength(200));
    });

    test('produces an id a fork accepts', () {
      final forked = Presets.standard.fork(id: ReadingProfile.newId());
      expect(forked.isBuiltIn, isFalse);
    });
  });
}
