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
    // The bug this guards against: text arriving already on screen rather
    // than sliding in from beyond the edge. `MarqueePainter` puts the anchor
    // `tokenOffset` into the current token, and the session holds that offset
    // anywhere in [0, advance), so over the life of one token the viewport
    // spans [xOf(index) - behind, xOf(index) + advance + ahead). All of that,
    // plus the ink margin either side, must be measured at every token of a
    // walk through a long synthetic book — remeasuring only when the previous
    // window stopped being usable, the way `ScrollClock` does — or something
    // unmeasured is on screen, and it appears in place when the next window
    // arrives.
    //
    // Measuring from the token's left edge instead is the shape of the
    // original defect: the window ran out on screen for the last stretch of
    // each token, widest across a paragraph or chapter gap.
    test('holds across viewport widths, type sizes and anchor positions', () {
      final text = TokenizedText.from([
        (id: 'one', text: List.generate(3000, (i) => 'word$i').join(' ')),
      ], parserVersion: 1);
      final tokenCount = text.tokens.length;

      // Gaps give a token an advance of several words, which is where the
      // anchor travels furthest without the index moving.
      bool isParagraphEnd(int i) => i % 11 == 10;
      const chapterStarts = {400, 1200, 2500};

      for (final width in [360.0, 1280.0, 2756.0, 5120.0]) {
        for (final fontSize in [13.0, 44.0, 96.0]) {
          for (final anchorX in [0.2, 0.5, 0.8]) {
            final style = TextStyle(fontSize: fontSize, height: 1.2);
            final styleKey = ('prop', fontSize, 0.0);
            final margin = fontSize * scrollInkMarginEm;
            final viewAhead = (1 - anchorX) * width;
            final viewBehind = anchorX * width;
            // What `ScrollClock` asks for: the viewport and the margin.
            final aheadPx = viewAhead + margin;
            final behindPx = viewBehind + margin;
            final where = 'width=$width fontSize=$fontSize anchorX=$anchorX';

            bool usable(ScrollLayout? layout, int index) =>
                scrollLayoutIsUsable(
                  layout,
                  index: index,
                  tokenCount: tokenCount,
                  styleKey: styleKey,
                  aheadPx: aheadPx,
                  behindPx: behindPx,
                );

            ScrollLayout? layout;
            double? previousMean;

            try {
              for (var index = 0; index < tokenCount; index++) {
                if (!usable(layout, index)) {
                  layout?.dispose();
                  layout = measureRun(
                    tokens: text.tokens,
                    index: index,
                    style: style,
                    styleKey: styleKey,
                    chapterStarts: chapterStarts,
                    isParagraphEnd: isParagraphEnd,
                    aheadPx: aheadPx,
                    behindPx: behindPx,
                    previousMeanAdvance: previousMean,
                  );
                  previousMean = layout.run.meanAdvance;

                  expect(
                    usable(layout, index),
                    isTrue,
                    reason:
                        '$where index=$index: a fresh window the caller '
                        'rejects is re-measured on every frame',
                  );
                }

                final current = layout!;
                final atStart = current.firstIndex == 0;
                final atEnd = current.lastIndex == tokenCount - 1;
                final viewLeft = current.xOf(index) - viewBehind;
                final viewRight =
                    current.xOf(index) +
                    current.run.advanceAt(index) +
                    viewAhead;

                expect(
                  atStart || viewLeft >= margin - 0.5,
                  isTrue,
                  reason: '$where index=$index: behind short of the viewport',
                );
                expect(
                  atEnd || current.rightEdge >= viewRight + margin - 0.5,
                  isTrue,
                  reason:
                      '$where index=$index: the viewport passes the measured '
                      'text before the index moves',
                );
              }
            } finally {
              layout?.dispose();
            }
          }
        }
      }
    });

    test('a replacement window draws every shared token where it was', () {
      // The clock swaps windows mid-scroll, anchored on the current token.
      // Any token both windows hold must keep its distance from that anchor,
      // and the anchor token its advance — `PlaybackSession.run` rescales the
      // offset by it — or the swap moves text that is on screen.
      final text = _longText();
      bool isParagraphEnd(int i) => i % 11 == 10;

      ScrollLayout at(int index) => measureRun(
        tokens: text.tokens,
        index: index,
        style: _style,
        styleKey: _key,
        chapterStarts: const {60},
        isParagraphEnd: isParagraphEnd,
        aheadPx: 2000,
        behindPx: 600,
      );

      final before = at(80);
      final after = at(90);
      addTearDown(before.dispose);
      addTearDown(after.dispose);

      const anchor = 90;
      for (final layout in [before, after]) {
        expect(
          anchor,
          inInclusiveRange(layout.firstIndex, layout.lastIndex),
          reason: 'both windows must hold the anchor, or xOf falls back',
        );
      }
      expect(
        after.run.advanceAt(anchor),
        closeTo(before.run.advanceAt(anchor), 0.01),
      );

      final shared = [
        for (
          var i = after.firstIndex > before.firstIndex
              ? after.firstIndex
              : before.firstIndex;
          i <= before.lastIndex && i <= after.lastIndex;
          i++
        )
          i,
      ];
      expect(shared.length, greaterThan(10));

      for (final i in shared) {
        expect(
          after.xOf(i) - after.xOf(anchor),
          closeTo(before.xOf(i) - before.xOf(anchor), 0.01),
          reason: 'token $i moved when the window was replaced',
        );
      }
    });
  });
}
