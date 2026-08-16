import 'package:rsvp_engine/rsvp_engine.dart';
import 'package:test/test.dart';

void main() {
  group('remainingReadingTime', () {
    test('a constant-paced book takes its word count over its rate', () {
      // 250 wpm is 240 ms a word, so 25000 words is 100 minutes.
      final left = remainingReadingTime(
        remainingTokens: 25000,
        config: const PacingConfig(baseWpm: 250),
      );

      expect(left, const Duration(minutes: 100));
    });

    test('length-scaled pacing estimates at the reference length', () {
      const tokens = 1000;
      const constant = PacingConfig(baseWpm: 300);
      const scaled = PacingConfig(
        kind: PacingModelKind.lengthScaled,
        baseWpm: 300,
      );

      expect(
        remainingReadingTime(remainingTokens: tokens, config: scaled),
        remainingReadingTime(remainingTokens: tokens, config: constant),
      );
    });

    test('elicited pacing has no estimate at all', () {
      final left = remainingReadingTime(
        remainingTokens: 25000,
        config: const PacingConfig(kind: PacingModelKind.elicited),
      );

      expect(left, isNull);
    });

    test('minDisplay bounds the estimate, as it bounds a real run', () {
      // 3000 wpm asks for 20 ms a word and minDisplay holds it at 40, so an
      // estimate reading off baseWpm alone would promise half the time the
      // book actually takes.
      final left = remainingReadingTime(
        remainingTokens: 1000,
        config: const PacingConfig(
          baseWpm: 3000,
          minDisplay: Duration(milliseconds: 40),
        ),
      );

      expect(left, const Duration(seconds: 40));
    });

    test('nothing left takes no time', () {
      expect(
        remainingReadingTime(
          remainingTokens: 0,
          config: const PacingConfig(),
        ),
        Duration.zero,
      );
    });

    test('a negative count is treated as nothing left', () {
      // Reachable: tokenIndex is a hint from whichever build wrote it, and
      // a kParserVersion bump can leave it past a wordCount counted by the
      // current tokenizer. A negative duration would print as a negative
      // number of minutes.
      expect(
        remainingReadingTime(
          remainingTokens: -50,
          config: const PacingConfig(),
        ),
        Duration.zero,
      );
    });
  });
}
