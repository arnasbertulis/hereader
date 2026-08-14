import 'package:rsvp_engine/rsvp_engine.dart';
import 'package:test/test.dart';

const _paragraph = '''
The reader sees one word at a time, anchored in a fixed position on the
screen. Because the eye does not move, there are no regressions and no
parafoveal preview; the word arrives at the retina instead of the retina
seeking the word. This helps some readers, hinders others, and the
difference is large enough that a single fixed rate cannot serve both.
''';

/// Effective words-per-minute implied by a list of decisions.
double _wpm(int tokenCount, Duration elapsed) =>
    tokenCount / (elapsed.inMicroseconds / 60000000);

({Duration display, Duration total}) _run(
  List<Token> tokens,
  PacingConfig config,
) {
  final model = PacingModel.of(config.kind);
  var display = Duration.zero;
  var total = Duration.zero;
  for (final t in tokens) {
    final d = model.decide(t, config);
    if (d is Hold) {
      display += d.display;
      total += d.total;
    } else {
      fail('paragraph timing is meaningless for AwaitAdvance');
    }
  }
  return (display: display, total: total);
}

void main() {
  final tokens = Tokenizer().tokenize(_paragraph);

  setUp(() {
    expect(
      tokens.length,
      greaterThan(40),
      reason: 'fixture should be long enough for rates to be meaningful',
    );
  });

  group('constant pacing over a real paragraph', () {
    const config = PacingConfig(baseWpm: 300);

    test('display-only rate equals baseWpm', () {
      final r = _run(tokens, config);
      expect(_wpm(tokens.length, r.display), closeTo(300, 0.5));
    });

    test('pause overhead stays within budget', () {
      final r = _run(tokens, config);
      final overhead =
          (r.total.inMicroseconds - r.display.inMicroseconds) /
          r.display.inMicroseconds;
      expect(
        overhead,
        lessThan(0.25),
        reason: 'punctuation pauses should cost under 25% of reading time',
      );
    });
  });

  group('lengthScaled pacing over a real paragraph', () {
    const config = PacingConfig(
      kind: PacingModelKind.lengthScaled,
      baseWpm: 300,
    );

    test('display-only rate tracks reference/mean letter ratio', () {
      final r = _run(tokens, config);
      final meanLetters =
          tokens.map((t) => t.letterCount).reduce((a, b) => a + b) /
          tokens.length;
      final expected = 300 * config.referenceLetterCount / meanLetters;
      expect(
        _wpm(tokens.length, r.display),
        closeTo(expected, expected * 0.02),
      );
    });

    test('stays within 20% of baseWpm on ordinary English prose', () {
      final r = _run(tokens, config);
      expect(
        _wpm(tokens.length, r.display),
        closeTo(300, 60),
        reason:
            'reference length of 5 should suit typical English; '
            'a large miss means referenceLetterCount needs revisiting',
      );
    });
  });
}
