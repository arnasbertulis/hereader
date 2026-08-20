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
}) => measureRun(
  tokens: text.tokens,
  index: index,
  style: style,
  styleKey: styleKey,
  chapterStarts: chapterStarts,
  isParagraphEnd: text.isParagraphEndAt,
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
    test('is asymmetric: more ahead than behind', () {
      final layout = _measure(_longText(), index: 100);

      expect(layout.run.firstIndex, 100 - scrollWindowBefore);
      expect(layout.run.lastIndex, 100 + scrollWindowAfter);
    });

    test('clamps at both ends of the text', () {
      final start = _measure(_longText());
      expect(start.run.firstIndex, 0);

      final end = _measure(_longText(), index: 199);
      expect(end.run.lastIndex, 199);
    });

    test('is reused while the anchor stays clear of its edges', () {
      final layout = _measure(_longText(), index: 100);

      for (final index in [100, 101, 120, 140]) {
        expect(
          scrollLayoutIsUsable(
            layout,
            index: index,
            tokenCount: 200,
            styleKey: _key,
          ),
          isTrue,
          reason: 'still covered at $index',
        );
      }
    });

    test('is rebuilt when the anchor nears an edge', () {
      final layout = _measure(_longText(), index: 100);

      for (final index in [86, 143, 40, 180]) {
        expect(
          scrollLayoutIsUsable(
            layout,
            index: index,
            tokenCount: 200,
            styleKey: _key,
          ),
          isFalse,
          reason: 'too close to an edge at $index',
        );
      }
    });

    test('the ends of the text are not edges to run from', () {
      // The window already reaches token 0, so being three tokens from its
      // start is not a reason to measure again — there is nothing there.
      final layout = _measure(_longText());

      expect(
        scrollLayoutIsUsable(layout, index: 2, tokenCount: 200, styleKey: _key),
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
        ),
        isFalse,
      );
    });

    test('null is never usable', () {
      expect(
        scrollLayoutIsUsable(null, index: 0, tokenCount: 200, styleKey: _key),
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
    );

    expect(layout.isEmpty, isTrue);
    expect(layout.run.meanAdvance, greaterThan(0));
  });
}
