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

/// A longer text with no boundary in it, so only the chunk cap cuts it.
TokenizedText _longText([int count = 200]) => TokenizedText.from([
  (id: 'one', text: List.generate(count, (i) => 'word$i').join(' ')),
], parserVersion: 1);

const _style = TextStyle(fontSize: 20, height: 1.2);
const _key = ('test', 20.0, 0.0);

ScrollLayout _cover(
  TokenizedText text, {
  ScrollLayout? current,
  int index = 0,
  Set<int> chapterStarts = const {},
  bool Function(int)? isParagraphEnd,
  TextStyle style = _style,
  ScrollStyleKey styleKey = _key,
  double aheadPx = 1000,
  double behindPx = 200,
  double slackPx = 1000,
  bool relayout = false,
}) => coverRun(
  current: current,
  tokens: text.tokens,
  index: index,
  style: style,
  styleKey: styleKey,
  chapterStarts: chapterStarts,
  isParagraphEnd: isParagraphEnd ?? text.isParagraphEndAt,
  aheadPx: aheadPx,
  behindPx: behindPx,
  slackPx: slackPx,
  relayout: relayout,
);

/// Whether [a] and [b] hold [index] in the one and the same chunk object.
bool _sameChunkAt(ScrollLayout a, ScrollLayout b, int index) {
  ScrollSegment? holding(ScrollLayout l) {
    for (final s in l.segments) {
      if (s.holds(index)) return s;
    }
    return null;
  }

  return identical(holding(a), holding(b));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('advances', () {
    test('cover every token in the strip, in order', () {
      final layout = _cover(_text());

      expect(layout.run.firstIndex, 0);
      expect(layout.run.lastIndex, 8);
      expect(layout.run.advances, hasLength(9));
      expect(layout.run.advances.every((a) => a > 0), isTrue);
    });

    test('a paragraph end is wider than an ordinary word gap', () {
      final layout = _cover(_text());

      // Token 2 ends block one; token 1 is mid-paragraph. Both are three to
      // five letters, so the difference is the boundary and not the word.
      expect(layout.run.advanceAt(2), greaterThan(layout.run.advanceAt(1)));
    });

    test('a chapter is wider still', () {
      final plain = _cover(_text());
      final withChapter = _cover(_text(), chapterStarts: const {3});

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
      double at({bool paragraph = false, Set<int> chapterStarts = const {}}) =>
          _cover(
            text,
            chapterStarts: chapterStarts,
            isParagraphEnd: (i) => paragraph && i == 5,
          ).run.advanceAt(5);

      final plain = at();

      expect(
        at(paragraph: true) - plain,
        closeTo(20 * scrollParagraphGapEm, 0.5),
      );
      expect(
        at(chapterStarts: const {6}) - plain,
        closeTo(20 * scrollChapterGapEm, 0.5),
      );
    });

    test('a fresh strip takes the measured average as its mean', () {
      final layout = _cover(_text());
      final total = layout.run.advances.fold<double>(0, (a, b) => a + b);

      expect(
        layout.run.meanAdvance,
        closeTo(total / layout.run.advances.length, 0.001),
      );
    });
  });

  group('chunks', () {
    test('are cut at every paragraph', () {
      final layout = _cover(_text());

      expect(layout.segments.map((s) => s.firstIndex), [0, 3, 6]);
    });

    test('are cut at the cap where no boundary comes first', () {
      // The test font sets every glyph an em square, so a chunk of the cap
      // is about 4500 px here; ask for more than one chunk can cover.
      final layout = _cover(_longText(), aheadPx: 12000);

      expect(layout.segments.length, greaterThan(1));
      for (final segment in layout.segments) {
        expect(segment.tokenX.length, lessThanOrEqualTo(scrollChunkMaxTokens));
      }
    });

    test('a chapter cuts as well as a paragraph', () {
      final layout = _cover(
        _longText(),
        chapterStarts: const {10},
        aheadPx: 3000,
      );
      expect(layout.segments.map((s) => s.firstIndex), contains(10));
    });

    test('x positions rise across the strip and match the advances', () {
      // Across paragraph cuts and across cap cuts alike: the gap drawn after
      // a token is the one the session walks.
      for (final layout in [
        _cover(_text()),
        _cover(_longText(), index: 100, aheadPx: 3000, behindPx: 1500),
      ]) {
        for (var i = layout.firstIndex; i < layout.lastIndex; i++) {
          expect(
            layout.xOf(i + 1) - layout.xOf(i),
            closeTo(layout.run.advanceAt(i), 0.001),
            reason: 'the gap drawn after token $i is the one the session walks',
          );
        }
      }
    });
  });

  group('the strip', () {
    test('clamps at both ends of the text', () {
      expect(_cover(_longText()).firstIndex, 0);
      expect(_cover(_longText(), index: 199).lastIndex, 199);
    });

    test('is returned unchanged while it still covers the targets', () {
      final text = _longText();
      final layout = _cover(text, index: 100);

      expect(
        identical(_cover(text, current: layout, index: 100), layout),
        isTrue,
      );
      expect(
        identical(_cover(text, current: layout, index: 101), layout),
        isTrue,
      );
    });

    test('keeps every chunk it already held when it grows', () {
      final text = _longText();
      final first = _cover(text, index: 20, aheadPx: 600, behindPx: 200);
      final later = _cover(
        text,
        current: first,
        index: first.lastIndex - 1,
        aheadPx: 600,
        behindPx: 200,
      );

      expect(later.lastIndex, greaterThan(first.lastIndex));
      for (var i = later.firstIndex; i <= first.lastIndex; i++) {
        expect(_sameChunkAt(first, later, i), isTrue, reason: 'token $i');
      }
    });

    test('starts over for a seek outside it, keeping its speed', () {
      final text = _longText(2000);
      final here = _cover(text, index: 10);
      final there = _cover(text, current: here, index: 1500);

      expect(there.segments.any(here.segments.contains), isFalse);
      expect(there.run.meanAdvance, here.run.meanAdvance);
    });

    test('starts over and takes a new speed for a new type style', () {
      final text = _longText();
      final small = _cover(text, index: 100);
      final large = _cover(
        text,
        current: small,
        index: 100,
        style: const TextStyle(fontSize: 40, height: 1.2),
        styleKey: ('test', 40.0, 0.0),
      );

      expect(large.segments.any(small.segments.contains), isFalse);
      expect(large.run.meanAdvance, greaterThan(small.run.meanAdvance));
    });

    test('starts over for a font that arrived', () {
      final text = _longText();
      final before = _cover(text, index: 100);
      final after = _cover(text, current: before, index: 100, relayout: true);

      expect(after.segments.any(before.segments.contains), isFalse);
    });
  });

  test('an empty text measures to nothing usable', () {
    final layout = coverRun(
      current: null,
      tokens: const [],
      index: 0,
      style: _style,
      styleKey: _key,
      chapterStarts: const {},
      isParagraphEnd: (_) => false,
      aheadPx: 1000,
      behindPx: 200,
      slackPx: 1000,
    );

    expect(layout.isEmpty, isTrue);
    expect(layout.run.meanAdvance, greaterThan(0));
  });

  group('reading through a book', () {
    // The two defects this guards against, both seen on screen: text
    // arriving already in view rather than sliding in from beyond the edge,
    // and the line changing speed and shuffling as the measured text was
    // replaced under it.
    //
    // `MarqueePainter` puts the anchor `tokenOffset` into the current token,
    // and the session holds that offset anywhere in [0, advance), so over the
    // life of one token the viewport spans
    // [xOf(index) - behind, xOf(index) + advance + ahead). Walked one token
    // at a time — the clock covers on every frame, so no token is skipped —
    // in both directions through a long book:
    //
    // - that span plus the ink margin is always measured,
    // - a chunk joining the strip lies wholly outside the viewport as it
    //   stands when the anchor enters the token — at its left edge reading
    //   forward, at its far edge scrubbing back — so nothing is ever measured
    //   while it is visible,
    // - every token held before and after a step is held by the very same
    //   chunk, so nothing that was drawn is re-laid out, and
    // - the mean, and with it the velocity, never moves.
    test('holds across viewport widths, type sizes and anchor positions', () {
      final text = _longText(3000);
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
            final where = 'width=$width fontSize=$fontSize anchorX=$anchorX';

            ScrollLayout? layout;
            final held = <TextPainter>{};

            void step(int index, {required bool forward}) {
              final previous = layout;
              // What `ScrollClock` asks for: the viewport, the margin and a
              // viewport of lead on each side.
              final next = coverRun(
                current: previous,
                tokens: text.tokens,
                index: index,
                style: style,
                styleKey: styleKey,
                chapterStarts: chapterStarts,
                isParagraphEnd: isParagraphEnd,
                aheadPx: viewAhead + margin + width,
                behindPx: viewBehind + margin + width,
                slackPx: width,
              );
              layout = next;

              final atStart = next.firstIndex == 0;
              final atEnd = next.lastIndex == tokenCount - 1;
              final viewLeft = next.xOf(index) - viewBehind - margin;
              final viewRight =
                  next.xOf(index) +
                  next.run.advanceAt(index) +
                  viewAhead +
                  margin;

              expect(
                atStart || next.leftEdge <= viewLeft + 0.5,
                isTrue,
                reason: '$where index=$index: behind short of the viewport',
              );
              expect(
                atEnd || next.rightEdge >= viewRight - 0.5,
                isTrue,
                reason:
                    '$where index=$index: the viewport passes the measured '
                    'text before the index moves',
              );

              if (previous == null || identical(previous, next)) {
                held
                  ..clear()
                  ..addAll(next.segments.map((s) => s.painter));
                return;
              }

              expect(
                next.run.meanAdvance,
                previous.run.meanAdvance,
                reason: '$where index=$index: the speed changed',
              );

              for (var i = next.firstIndex; i <= next.lastIndex; i++) {
                if (i < previous.firstIndex || i > previous.lastIndex) continue;
                expect(
                  _sameChunkAt(previous, next, i),
                  isTrue,
                  reason: '$where index=$index: token $i was re-measured',
                );
              }

              for (final segment in next.segments) {
                if (held.contains(segment.painter)) continue;
                final entry = forward
                    ? next.xOf(index)
                    : next.xOf(index) + next.run.advanceAt(index);
                final visible =
                    segment.textEnd > entry - viewBehind - margin &&
                    segment.startX < entry + viewAhead + margin;
                expect(
                  visible,
                  isFalse,
                  reason:
                      '$where index=$index: chunk at ${segment.firstIndex} '
                      'was measured in view',
                );
              }

              held
                ..clear()
                ..addAll(next.segments.map((s) => s.painter));
            }

            try {
              for (var index = 0; index < tokenCount; index++) {
                step(index, forward: true);
              }
              for (var index = tokenCount - 1; index >= 0; index--) {
                step(index, forward: false);
              }
              // Shedding keeps a long read bounded: the strip is a few
              // viewports and a chunk either side, not the book.
              expect(
                layout!.rightEdge - layout!.leftEdge,
                lessThan(
                  2 * (width + margin + width) +
                      3 * width +
                      4 * scrollChunkMaxTokens * fontSize * 8,
                ),
                reason: where,
              );
            } finally {
              layout?.dispose();
            }
          }
        }
      }
    });
  });
}
