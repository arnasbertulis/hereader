import 'package:app/reading/profile_presentation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

ReadingProfile _profile({required int fadeMs, PacingConfig? pacing}) =>
    ReadingProfile(
      id: 'p.test',
      name: 'Test',
      pacing: pacing ?? const PacingConfig(),
      presentation: PresentationConfig(transitionMs: fadeMs),
    );

void main() {
  group('the fade warning', () {
    // 250 wpm is a 240 ms hold, and the slider reaches 300.
    test('fires when the fade outlasts the word', () {
      expect(fadeWarning(_profile(fadeMs: 300)), isNotNull);
    });

    test('stays quiet at or under the hold', () {
      expect(fadeWarning(_profile(fadeMs: 240)), isNull);
      expect(fadeWarning(_profile(fadeMs: 60)), isNull);
      expect(fadeWarning(_profile(fadeMs: 0)), isNull);
    });

    // Nothing to outlast: the word waits for the reader.
    test('stays quiet under elicited pacing at any length', () {
      expect(
        fadeWarning(
          _profile(
            fadeMs: 300,
            pacing: const PacingConfig(kind: PacingModelKind.elicited),
          ),
        ),
        isNull,
      );
    });

    // The two settings are coupled from both ends: slowing down can silence
    // the warning without the fade changing at all.
    test('follows the rate as well as the fade', () {
      const slow = PacingConfig(baseWpm: 120);
      expect(fadeWarning(_profile(fadeMs: 300, pacing: slow)), isNull);
    });
  });
}
