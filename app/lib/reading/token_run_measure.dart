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

/// Tokens measured behind the anchor, used only as a fallback estimate
/// before a viewport width is known. Fewer than ahead, because text enters
/// from the right and leaves on the left: most of what has to be on screen is
/// still coming.
const int scrollFallbackWindowBefore = 16;

/// Tokens measured ahead of the anchor, used only as a fallback estimate
/// before a viewport width is known.
const int scrollFallbackWindowAfter = 48;

/// Assumed pixels a token advances, as a multiple of the type size, before
/// any layout has been measured. A deliberately rough starting point that
/// [measureRun] corrects from its own measurement on its first widening
/// pass — never a claim about any particular book.
const double scrollAdvanceGuessEm = 3.0;

/// How much wider than the required pixel extent [measureRun] targets, so an
/// ordinary read crosses many pixels per rebuild rather than re-measuring on
/// each one.
const double scrollMeasureSlack = 1.5;

/// Coverage kept past each edge of the viewport, as a multiple of the type
/// size.
///
/// A glyph's ink is not confined to its advance: an italic, a `j`, an `f` or
/// a stacked diacritic reaches into the space beside it. A token measured
/// only up to the viewport edge could still put ink across it that nothing
/// had drawn, and it would appear in place when the next window arrived. An
/// em is wider than any such overhang a reading face draws, and costs one
/// extra word of layout per side.
const double scrollInkMarginEm = 1.0;

/// Bound on how many times [measureRun] widens its guess and re-measures.
/// Each attempt is one `TextPainter.layout` per segment, so this is a
/// ceiling on that cost, not an expected count.
const int scrollMeasureMaxAttempts = 6;

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

  /// Right edge of the last measured token, in this layout's coordinate
  /// space. The first token's left edge is always 0 ([measureRun] starts its
  /// cursor there), so this doubles as the layout's total measured extent.
  double get rightEdge {
    if (segments.isEmpty) return 0;
    final last = segments.last;
    return last.startX + last.painter.width;
  }

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

/// Whether [layout] still covers [index] by at least [aheadPx] ahead and
/// [behindPx] behind, in painted pixels — the coverage a caller needs to
/// fill its viewport on both sides of the anchor without a blank gap. A side
/// is exempt only where the book itself ends on that side of the layout.
bool scrollLayoutIsUsable(
  ScrollLayout? layout, {
  required int index,
  required int tokenCount,
  required ScrollStyleKey styleKey,
  required double aheadPx,
  required double behindPx,
}) {
  if (layout == null || layout.isEmpty) return false;
  if (layout.styleKey != styleKey) return false;
  if (index < layout.firstIndex || index > layout.lastIndex) return false;

  final atBookStart = layout.firstIndex == 0;
  final atBookEnd = layout.lastIndex == tokenCount - 1;

  // The anchor only ever moves forward through a token from its left edge,
  // so the viewport's left edge never sits further back than it does at
  // `tokenOffset` zero, and the left edge of [index] is the right place to
  // measure from.
  final behindCovered = layout.xOf(index);
  if (!atBookStart && behindCovered < behindPx) return false;

  // From the current token's far edge, not its left one. The anchor travels
  // up to a whole advance into the token before the index moves — a word, or
  // a word plus a chapter gap — and the viewport's right edge travels with
  // it. Measured from the left edge, the window ran out on screen for the
  // last stretch of a token, and the remeasure the next token triggered drew
  // the missing text already in view.
  final aheadCovered =
      layout.rightEdge - (layout.xOf(index) + layout.run.advanceAt(index));
  if (!atBookEnd && aheadCovered < aheadPx) return false;

  return true;
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
///
/// [aheadPx] and [behindPx] are the pixel extents the caller needs covered
/// on each side of [index] — see [scrollLayoutIsUsable]. This measures a
/// window sized to meet them: it picks a token count from [previousMeanAdvance]
/// (or a type-size guess when there is none yet), measures, and widens and
/// re-measures if the actual coverage came up short, up to
/// [scrollMeasureMaxAttempts] times.
ScrollLayout measureRun({
  required List<Token> tokens,
  required int index,
  required TextStyle style,
  required ScrollStyleKey styleKey,
  required Set<int> chapterStarts,
  required bool Function(int) isParagraphEnd,
  required double aheadPx,
  required double behindPx,
  double? previousMeanAdvance,
}) {
  if (tokens.isEmpty) {
    return ScrollLayout(
      segments: const [],
      run: TokenRun.empty,
      styleKey: styleKey,
    );
  }

  final fontSize = style.fontSize ?? 16;
  var estimate = (previousMeanAdvance != null && previousMeanAdvance > 0)
      ? previousMeanAdvance
      : fontSize * scrollAdvanceGuessEm;

  ScrollLayout? layout;

  for (var attempt = 0; attempt < scrollMeasureMaxAttempts; attempt++) {
    // +1 token ahead for the current token itself: coverage is counted from
    // its far edge, see [scrollLayoutIsUsable].
    final aheadTokens = ((aheadPx * scrollMeasureSlack) / estimate).ceil() + 1;
    final behindTokens = ((behindPx * scrollMeasureSlack) / estimate).ceil();

    final first = (index - behindTokens).clamp(0, tokens.length - 1);
    final last = (index + aheadTokens).clamp(0, tokens.length - 1);

    layout?.dispose();
    layout = _measureWindow(
      tokens: tokens,
      first: first,
      last: last,
      style: style,
      styleKey: styleKey,
      chapterStarts: chapterStarts,
      isParagraphEnd: isParagraphEnd,
      fontSize: fontSize,
    );

    // The same test the caller will apply on its next tick. A second copy of
    // the coverage rule here could accept a window the caller then rejects,
    // and it would re-measure on every frame. Covers the whole-book case too:
    // with both ends exempt there is nothing wider to measure.
    if (scrollLayoutIsUsable(
      layout,
      index: index,
      tokenCount: tokens.length,
      styleKey: styleKey,
      aheadPx: aheadPx,
      behindPx: behindPx,
    )) {
      return layout;
    }

    // Re-estimate from what was actually measured; only force growth by
    // brute multiplication if the measured mean did not move the estimate
    // (e.g. a run of same-length tokens), so this cannot loop without
    // widening the window.
    estimate = layout.run.meanAdvance > estimate
        ? layout.run.meanAdvance
        : estimate * 1.5;
  }

  return layout!;
}

ScrollLayout _measureWindow({
  required List<Token> tokens,
  required int first,
  required int last,
  required TextStyle style,
  required ScrollStyleKey styleKey,
  required Set<int> chapterStarts,
  required bool Function(int) isParagraphEnd,
  required double fontSize,
}) {
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
