import 'package:flutter/widgets.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// Measures the tokens around the anchor for continuous scroll.
///
/// The engine imports no Flutter and measures nothing, so it is handed its
/// geometry as a [TokenRun]. This file is where that geometry comes from, and
/// it produces the paint data in the same pass — one object holds both, so
/// the widget cannot draw a token in a place the session does not think it
/// is. Two measurements of one layout is how they come apart.
///
/// A window, never the book. Laying out a whole book to scroll it would cost
/// a pass proportional to its length on web, where `compute()` does not
/// offload; ADR 0025 rejects it.

/// Blank width after a paragraph, as a multiple of the type size.
const double scrollParagraphGapEm = 2.0;

/// Blank width before a chapter, as a multiple of the type size. Wider than
/// a paragraph so the two boundaries are distinguishable at a glance without
/// either becoming a wait.
const double scrollChapterGapEm = 6.0;

/// Tokens measured behind the anchor. Fewer than ahead, because text enters
/// from the right and leaves on the left: most of what has to be on screen is
/// still coming.
const int scrollWindowBefore = 16;

/// Tokens measured ahead of the anchor.
const int scrollWindowAfter = 48;

/// How close the anchor may get to a measured edge before the window is
/// rebuilt. Above zero so an ordinary read crosses many tokens per rebuild
/// rather than re-measuring on each one.
const int scrollWindowMargin = 6;

/// Identity of the type style a layout was measured under.
///
/// A record rather than the [TextStyle] itself, so equality is by value and
/// a rebuilt style object with identical fields does not invalidate a
/// perfectly good measurement.
typedef ScrollStyleKey = (String?, double, double);

ScrollStyleKey scrollStyleKeyFor(PresentationConfig config) =>
    (config.fontFamily, config.fontSizePt, config.letterSpacingEm);

/// One unbroken stretch of text, laid out as a single line.
///
/// The window is cut at paragraph and chapter boundaries, and the blank at
/// each cut is expressed as a gap between segments rather than as spaces in
/// the string. Inside a segment the text is shaped as one run, so kerning is
/// what a page of this book would show.
class ScrollSegment {
  final TextPainter painter;

  /// Where this segment begins, in the layout's own coordinate space.
  final double startX;

  final int firstIndex;

  /// Left edge of each token relative to [startX].
  final List<double> tokenX;

  const ScrollSegment({
    required this.painter,
    required this.startX,
    required this.firstIndex,
    required this.tokenX,
  });

  int get lastIndex => firstIndex + tokenX.length - 1;
}

/// A measured window: what to paint, and the [TokenRun] the session walks.
class ScrollLayout {
  final List<ScrollSegment> segments;

  /// Handed to `PlaybackSession.run`. Its advances are the distances between
  /// the very token positions [segments] will be painted at.
  final TokenRun run;

  final ScrollStyleKey styleKey;

  const ScrollLayout({
    required this.segments,
    required this.run,
    required this.styleKey,
  });

  int get firstIndex => run.firstIndex;
  int get lastIndex => run.lastIndex;
  bool get isEmpty => segments.isEmpty;

  /// Left edge of [index] in this layout's coordinate space.
  ///
  /// Falls back to the mean beyond the window so a painter asked about a
  /// token it does not hold draws off-screen rather than throwing.
  double xOf(int index) {
    for (final segment in segments) {
      if (index >= segment.firstIndex && index <= segment.lastIndex) {
        return segment.startX + segment.tokenX[index - segment.firstIndex];
      }
    }
    return (index - firstIndex) * run.meanAdvance;
  }

  void dispose() {
    for (final segment in segments) {
      segment.painter.dispose();
    }
  }
}

/// Whether [layout] still covers [index] with room to spare.
///
/// The margin is what keeps this off the per-token path: an ordinary read
/// crosses [scrollWindowAfter] minus [scrollWindowMargin] tokens between
/// rebuilds, and a rebuild is one `TextPainter.layout` per segment rather
/// than per token.
bool scrollLayoutIsUsable(
  ScrollLayout? layout, {
  required int index,
  required int tokenCount,
  required ScrollStyleKey styleKey,
}) {
  if (layout == null || layout.isEmpty) return false;
  if (layout.styleKey != styleKey) return false;

  final nearStart =
      layout.firstIndex > 0 && index - layout.firstIndex < scrollWindowMargin;
  final nearEnd =
      layout.lastIndex < tokenCount - 1 &&
      layout.lastIndex - index < scrollWindowMargin;

  return index >= layout.firstIndex &&
      index <= layout.lastIndex &&
      !nearStart &&
      !nearEnd;
}

/// Lay out the window of tokens around [index].
///
/// [chapterStarts] holds token indices that begin a chapter. Chapters are an
/// `app/` concept rather than a `TokenizedText` one, so a note or an EPUB
/// with no table of contents passes an empty set and gets paragraph gaps
/// only — no boundary is invented for it, which is ADR 0010's rule in
/// another place.
///
/// [isParagraphEnd] is `TokenizedText.isParagraphEndAt`. Passed in rather
/// than re-derived, so the blank this draws after a paragraph and the token
/// the paragraph jump lands on cannot describe different places.
///
/// Direction is pinned to [TextDirection.ltr] rather than read from the
/// ambient [Directionality]. An RTL ambient direction would mirror shaping
/// *within* each token while the run itself still travelled right to left,
/// which is worse than being consistently wrong; RTL is a stated limitation.
ScrollLayout measureRun({
  required List<Token> tokens,
  required int index,
  required TextStyle style,
  required ScrollStyleKey styleKey,
  required Set<int> chapterStarts,
  required bool Function(int) isParagraphEnd,
}) {
  if (tokens.isEmpty) {
    return ScrollLayout(
      segments: const [],
      run: TokenRun.empty,
      styleKey: styleKey,
    );
  }

  final fontSize = style.fontSize ?? 16;
  final first = (index - scrollWindowBefore).clamp(0, tokens.length - 1);
  final last = (index + scrollWindowAfter).clamp(0, tokens.length - 1);

  final spaceWidth = _spaceWidth(style, fontSize);

  final segments = <ScrollSegment>[];
  final advances = <double>[];
  var cursor = 0.0;

  var segmentStart = first;
  while (segmentStart <= last) {
    // Walk to the boundary that ends this segment, or to the window's edge.
    var segmentEnd = segmentStart;
    var trailingGap = 0.0;
    while (segmentEnd < last) {
      if (chapterStarts.contains(segmentEnd + 1)) {
        trailingGap = fontSize * scrollChapterGapEm;
        break;
      }
      if (isParagraphEnd(segmentEnd)) {
        trailingGap = fontSize * scrollParagraphGapEm;
        break;
      }
      segmentEnd++;
    }

    final buffer = StringBuffer();
    final starts = <int>[];
    for (var i = segmentStart; i <= segmentEnd; i++) {
      if (i > segmentStart) buffer.write(' ');
      starts.add(buffer.length);
      buffer.write(tokens[i].text);
    }

    final painter = _measure(buffer.toString(), style);

    // Caret offsets rather than `getBoxesForRange`: a box list can come back
    // empty for a range the shaper folded away, and a caret position is
    // defined for every character index in the string.
    final tokenX = [
      for (final start in starts)
        painter.getOffsetForCaret(TextPosition(offset: start), Rect.zero).dx,
    ];

    segments.add(
      ScrollSegment(
        painter: painter,
        startX: cursor,
        firstIndex: segmentStart,
        tokenX: tokenX,
      ),
    );

    // Advance from each token's left edge to the next one's. The last token
    // in a segment has no next edge to measure against, so it takes the rest
    // of the segment plus whatever the boundary adds.
    for (var i = 0; i < tokenX.length - 1; i++) {
      advances.add(tokenX[i + 1] - tokenX[i]);
    }
    advances.add(painter.width - tokenX.last + spaceWidth + trailingGap);

    cursor += painter.width + spaceWidth + trailingGap;
    segmentStart = segmentEnd + 1;
  }

  final total = advances.fold<double>(0, (sum, a) => sum + a);
  final mean = advances.isEmpty ? spaceWidth : total / advances.length;

  return ScrollLayout(
    segments: segments,
    run: TokenRun(
      firstIndex: first,
      advances: advances,
      meanAdvance: mean > 0 ? mean : fontSize,
    ),
    styleKey: styleKey,
  );
}

TextPainter _measure(String text, TextStyle style) => TextPainter(
  text: TextSpan(text: text, style: style),
  textDirection: TextDirection.ltr,
  maxLines: 1,
)..layout();

/// Width of the space between two tokens.
///
/// Measured as a difference rather than by laying out `' '` on its own:
/// `TextPainter.width` does not count whitespace at the end of a line, so a
/// lone space measures zero and every token would be drawn touching the next.
double _spaceWidth(TextStyle style, double fontSize) {
  final withSpace = _measure('x x', style);
  final without = _measure('xx', style);
  final width = withSpace.width - without.width;
  withSpace.dispose();
  without.dispose();

  return width > 0 ? width : fontSize * 0.25;
}
