// packages/rsvp_engine/test/pacing_test.dart

import 'package:rsvp_engine/rsvp_engine.dart';
import 'package:test/test.dart';

/// Minimal token builder for pacing tests.
/// Adjust to match your actual Token constructor.
Token _tok(String text, {PauseAfter pause = PauseAfter.none}) =>
    Token(text: text, charOffset: 0, pauseAfter: pause);

void main() {
  group('ConstantPacing', () {
    test('hits configured wpm', () {
      const c = PacingConfig(baseWpm: 300);
      final d = const ConstantPacing().decide(_tok('word'), c) as Hold;
      expect(d.display.inMilliseconds, 200);
    });

    test('ignores word length', () {
      const c = PacingConfig(baseWpm: 300);
      final short = const ConstantPacing().decide(_tok('a'), c) as Hold;
      final long =
          const ConstantPacing().decide(_tok('extraordinary'), c) as Hold;
      expect(short.display, long.display);
    });

    test('applies sentence pause', () {
      const c = PacingConfig(baseWpm: 300);
      final d =
          const ConstantPacing().decide(
                _tok('end.', pause: PauseAfter.sentence),
                c,
              )
              as Hold;
      expect(d.pauseAfter, c.sentencePause);
      expect(d.total, d.display + c.sentencePause);
    });
  });

  group('LengthScaledPacing', () {
    test('matches constant at reference length', () {
      const c = PacingConfig(kind: PacingModelKind.lengthScaled, baseWpm: 300);
      final d = const LengthScaledPacing().decide(_tok('hello'), c) as Hold;
      expect(d.display.inMilliseconds, 200);
    });

    test('longer words get longer holds', () {
      const c = PacingConfig(kind: PacingModelKind.lengthScaled, baseWpm: 300);
      final short = const LengthScaledPacing().decide(_tok('cat'), c) as Hold;
      final long =
          const LengthScaledPacing().decide(_tok('elephant'), c) as Hold;
      expect(long.display, greaterThan(short.display));
    });

    test('strength 0 degenerates to constant', () {
      const scaled = PacingConfig(
        kind: PacingModelKind.lengthScaled,
        baseWpm: 300,
        lengthScaleStrength: 0,
      );
      const flat = PacingConfig(baseWpm: 300);

      for (final word in ['a', 'hello', 'extraordinary']) {
        final s = const LengthScaledPacing().decide(_tok(word), scaled) as Hold;
        final f = const ConstantPacing().decide(_tok(word), flat) as Hold;
        expect(s.display, f.display, reason: 'mismatch on "$word"');
      }
    });

    test('clamps very long words to maxDisplay', () {
      const c = PacingConfig(
        kind: PacingModelKind.lengthScaled,
        baseWpm: 300,
        maxDisplay: Duration(milliseconds: 400),
      );
      final d =
          const LengthScaledPacing().decide(
                _tok('nebeprisikiškiakopūsteliaudamas'),
                c,
              )
              as Hold;
      expect(d.display, const Duration(milliseconds: 400));
    });
  });

  group('ElicitedPacing', () {
    test('never returns a timed hold', () {
      expect(
        const ElicitedPacing().decide(_tok('anything'), const PacingConfig()),
        isA<AwaitAdvance>(),
      );
    });

    test('ignores punctuation pauses', () {
      expect(
        const ElicitedPacing().decide(
          _tok('end.', pause: PauseAfter.sentence),
          const PacingConfig(),
        ),
        isA<AwaitAdvance>(),
      );
    });
  });

  group('PacingModel.of', () {
    test('maps each kind to its implementation', () {
      expect(PacingModel.of(PacingModelKind.constant), isA<ConstantPacing>());
      expect(
        PacingModel.of(PacingModelKind.lengthScaled),
        isA<LengthScaledPacing>(),
      );
      expect(PacingModel.of(PacingModelKind.elicited), isA<ElicitedPacing>());
    });
  });

  test('zero-letter token falls back to minDisplay', () {
    const c = PacingConfig(kind: PacingModelKind.lengthScaled, baseWpm: 300);
    final d = const LengthScaledPacing().decide(_tok('—'), c) as Hold;
    expect(d.display, c.minDisplay);
  });
}
