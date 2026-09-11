import 'package:app/reading/token_run_measure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// Three blocks of three words. Block boundaries are paragraph boundaries —
/// `HtmlNormalizer` emits one block per `<p>`, so for a real book they are
/// the only source that fires.
///
///   0 Alpha  1 beta     2 gamma.   | block one
///   3 Delta  4 epsilon  5 zeta.    | block two
///   6 Eta    7 theta    8 iota.    | block three
TokenizedText _text() => TokenizedText.from(const [
  (id: 'one', text: 'Alpha beta gamma.'),
  (id: 'two', text: 'Delta epsilon zeta.'),
  (id: 'three', text: 'Eta theta iota.'),
], parserVersion: 1);

/// A longer text, so the window has an edge inside it to test against.
TokenizedText _longText() => TokenizedText.from([
  (id: 'one', text: List.generate(200, (i) => 'word$i').join(' ')),
], parserVersion: 1);

const _style = TextStyle(fontSize: 20, height: 1.2);
const _key = ('test', 20.0, 0.0);

ScrollLayout _measure(
  TokenizedText text, {
  int index = 0,
  Set<int> chapterStarts = const {},
  TextStyle style = _style,
  ScrollStyleKey styleKey = _key,
  double aheadPx = 1000,
  double behindPx = 200,
}) => measureRun(
  tokens: text.tokens,
  index: index,
  style: style,
  styleKey: styleKey,
  chapterStarts: chapterStarts,
  isParagraphEnd: text.isParagraphEndAt,
  aheadPx: aheadPx,
  behindPx: behindPx,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('advances', () {
    test('cover every token in the window, in order', () {
      final layout = _measure(_text());

      expect(layout.run.firstIndex, 0);
      expect(layout.run.lastIndex, 8);
      expect(layout.run.advances, hasLength(9));
      expect(layout.run.advances.every((a) => a > 0), isTrue);
    });

    test('a paragraph end is wider than an ordinary word gap', () {
      final layout = _measure(_text());

      // Token 2 ends block one; token 1 is mid-paragraph. Both are three to
      // five letters, so the difference is the boundary and not the word.
      expect(layout.run.advanceAt(2), greaterThan(layout.run.advanceAt(1)));
    });

    test('a chapter is wider still', () {
      final plain = _measure(_text());
      final withChapter = _measure(_text(), chapterStarts: const {3});

      // Token 2 is both a paragraph end and, now, the token before a
      // chapter. The chapter wins and is the wider of the two.
      expect(withChapter.run.advanceAt(2), greaterThan(plain.run.advanceAt(2)));

      // Nothing else moves.
      expect(withChapter.run.advanceAt(1), plain.run.advanceAt(1));
    });

    test('the gaps are the documented multiples of the type size', () {
      // One token, measured three ways. Comparing two different tokens would
      // be measuring the difference between two words as well as the gap.
      final text = _longText();
      ScrollLayout at({
        bool paragraph = false,
        Set<int> chapterStarts = const {},
      }) => measureRun(
        tokens: text.tokens,
        index: 0,
        style: _style,
        styleKey: _key,
        chapterStarts: chapterStarts,
        isParagraphEnd: (i) => paragraph && i == 5,
        aheadPx: 1000,
        behindPx: 200,
      );

      final plain = at().run.advanceAt(5);

      expect(
        at(paragraph: true).run.advanceAt(5) - plain,
        closeTo(20 * scrollParagraphGapEm, 0.5),
      );
      expect(
        at(chapterStarts: const {6}).run.advanceAt(5) - plain,
        closeTo(20 * scrollChapterGapEm, 0.5),
      );
    });

    test('the mean is the measured average, not a guess', () {
      final layout = _measure(_text());
      final total = layout.run.advances.fold<double>(0, (a, b) => a + b);

      expect(
        layout.run.meanAdvance,
        closeTo(total / layout.run.advances.length, 0.001),
      );
    });
  });

  group('segments', () {
    test('the window is cut at every paragraph', () {
      final layout = _measure(_text());

      expect(layout.segments, hasLength(3));
      expect(layout.segments.map((s) => s.firstIndex), [0, 3, 6]);
    });

    test('a text with no boundaries inside the window is one segment', () {
      final layout = _measure(_longText());
      expect(layout.segments, hasLength(1));
    });

    test('a chapter cuts as well as a paragraph', () {
      final layout = _measure(_longText(), chapterStarts: const {10});
      expect(layout.segments, hasLength(2));
      expect(layout.segments.last.firstIndex, 10);
    });

    test('x positions rise across the window and match the advances', () {
      final layout = _measure(_text());

      for (var i = 0; i < 8; i++) {
        expect(
          layout.xOf(i + 1) - layout.xOf(i),
          closeTo(layout.run.advanceAt(i), 0.001),
          reason: 'the gap drawn after token $i is the one the session walks',
        );
      }
    });
  });

  group('the window', () {
    test('a wider ahead target measures further ahead than behind', () {
      final layout = _measure(
        _longText(),
        index: 100,
        aheadPx: 3000,
        behindPx: 200,
      );

      expect(
        layout.run.lastIndex - 100,
        greaterThan(100 - layout.run.firstIndex),
      );
    });

    test('clamps at both ends of the text', () {
      final start = _measure(_longText());
      expect(start.run.firstIndex, 0);

      final end = _measure(_longText(), index: 199);
      expect(end.run.lastIndex, 199);
    });

    test('is usable while the measured edges still cover the targets', () {
      const aheadPx = 500.0;
      const behindPx = 200.0;
      final layout = _measure(
        _longText(),
        index: 100,
        aheadPx: aheadPx,
        behindPx: behindPx,
      );

      for (final index in [100, 101, 105]) {
        expect(
          scrollLayoutIsUsable(
            layout,
            index: index,
            tokenCount: 200,
            styleKey: _key,
            aheadPx: aheadPx,
            behindPx: behindPx,
          ),
          isTrue,
          reason: 'still covered at $index',
        );
      }
    });

    test('is rebuilt once a measured edge is closer than the target', () {
      const aheadPx = 500.0;
      const behindPx = 200.0;
      final layout = _measure(
        _longText(),
        index: 100,
        aheadPx: aheadPx,
        behindPx: behindPx,
      );

      // At the layout's own last index, ahead coverage is zero — always
      // short of a positive target.
      expect(
        scrollLayoutIsUsable(
          layout,
          index: layout.lastIndex,
          tokenCount: 200,
          styleKey: _key,
          aheadPx: aheadPx,
          behindPx: behindPx,
        ),
        isFalse,
        reason: 'no pixels left ahead of the window edge',
      );

      // Symmetrically at the first index, behind coverage is zero.
      expect(
        scrollLayoutIsUsable(
          layout,
          index: layout.firstIndex,
          tokenCount: 200,
          styleKey: _key,
          aheadPx: aheadPx,
          behindPx: behindPx,
        ),
        isFalse,
        reason: 'no pixels left behind the window edge',
      );
    });

    test('the ends of the text are not edges to run from', () {
      // The window already reaches token 0, so having no pixels measured
      // behind it is not a reason to measure again — there is nothing there.
      final layout = _measure(_longText(), aheadPx: 500, behindPx: 200);

      expect(
        scrollLayoutIsUsable(
          layout,
          index: 2,
          tokenCount: 200,
          styleKey: _key,
          aheadPx: 500,
          behindPx: 200,
        ),
        isTrue,
      );
    });

    test('a style change invalidates it whatever the anchor is doing', () {
      final layout = _measure(_longText(), index: 100);

      expect(
        scrollLayoutIsUsable(
          layout,
          index: 100,
          tokenCount: 200,
          styleKey: ('test', 40.0, 0.0),
          aheadPx: 1000,
          behindPx: 200,
        ),
        isFalse,
      );
    });

    test('null is never usable', () {
      expect(
        scrollLayoutIsUsable(
          null,
          index: 0,
          tokenCount: 200,
          styleKey: _key,
          aheadPx: 1000,
          behindPx: 200,
        ),
        isFalse,
      );
    });
  });

  test('a bigger type size measures wider', () {
    final small = _measure(_longText());
    final large = _measure(
      _longText(),
      style: const TextStyle(fontSize: 40, height: 1.2),
      styleKey: ('test', 40.0, 0.0),
    );

    expect(large.run.meanAdvance, greaterThan(small.run.meanAdvance));
  });

  test('an empty text measures to nothing usable', () {
    final layout = measureRun(
      tokens: const [],
      index: 0,
      style: _style,
      styleKey: _key,
      chapterStarts: const {},
      isParagraphEnd: (_) => false,
      aheadPx: 1000,
      behindPx: 200,
    );

    expect(layout.isEmpty, isTrue);
    expect(layout.run.meanAdvance, greaterThan(0));
  });

  group('pixel coverage', () {
    // The bug this guards against: a fixed token-count window covers only a
    // few hundred pixels at a wide viewport or a large type size, so text
    // near the far edge of the screen has nothing measured to paint. For
    // every width, type size and anchor position below, whenever the window
    // is usable it must actually reach the required pixels on both sides —
    // "whenever" means at every step of a walk through a long synthetic
    // book, remeasuring only when the previous window stopped being usable,
    // the way `ScrollClock` does.
    test('holds across viewport widths, type sizes and anchor positions', () {
      final text = TokenizedText.from([
        (id: 'one', text: List.generate(3000, (i) => 'word$i').join(' ')),
      ], parserVersion: 1);
      final tokenCount = text.tokens.length;

      for (final width in [360.0, 1280.0, 2756.0, 5120.0]) {
        for (final fontSize in [13.0, 44.0, 96.0]) {
          for (final anchorX in [0.2, 0.5, 0.8]) {
            final style = TextStyle(fontSize: fontSize, height: 1.2);
            final styleKey = ('prop', fontSize, 0.0);
            final aheadPx = (1 - anchorX) * width;
            final behindPx = anchorX * width;
            final where = 'width=$width fontSize=$fontSize anchorX=$anchorX';

            ScrollLayout? layout;
            double? previousMean;

            try {
              for (var index = 0; index < tokenCount; index += 37) {
                if (!scrollLayoutIsUsable(
                  layout,
                  index: index,
                  tokenCount: tokenCount,
                  styleKey: styleKey,
                  aheadPx: aheadPx,
                  behindPx: behindPx,
                )) {
                  layout?.dispose();
                  layout = measureRun(
                    tokens: text.tokens,
                    index: index,
                    style: style,
                    styleKey: styleKey,
                    chapterStarts: const {},
                    isParagraphEnd: (_) => false,
                    aheadPx: aheadPx,
                    behindPx: behindPx,
                    previousMeanAdvance: previousMean,
                  );
                  previousMean = layout.run.meanAdvance;
                }

                final current = layout!;
                final atStart = current.firstIndex == 0;
                final atEnd = current.lastIndex == tokenCount - 1;
                final behindCovered = current.xOf(index);
                final aheadCovered = current.rightEdge - current.xOf(index);

                expect(
                  atStart || behindCovered >= behindPx - 0.5,
                  isTrue,
                  reason: '$where index=$index: behind short of target',
                );
                expect(
                  atEnd || aheadCovered >= aheadPx - 0.5,
                  isTrue,
                  reason: '$where index=$index: ahead short of target',
                );
              }
            } finally {
              layout?.dispose();
            }
          }
        }
      }
    });
  });
}
