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
/// A strip of chunks, never the book. Laying out a whole book to scroll it
/// would cost a pass proportional to its length on web, where `compute()`
/// does not offload; ADR 0025 rejects it. The strip grows a chunk at a time
/// ahead of the reader and sheds chunks behind, and a chunk once measured is
/// never measured again while it is held — see [coverRun].

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
/// any layout has been measured. Converts the fallback token counts to
/// pixels — never a claim about any particular book.
const double scrollAdvanceGuessEm = 3.0;

/// Coverage kept past each edge of the viewport, as a multiple of the type
/// size.
///
/// A glyph's ink is not confined to its advance: an italic, a `j`, an `f` or
/// a stacked diacritic reaches into the space beside it. A token measured
/// only up to the viewport edge could still put ink across it that nothing
/// had drawn, and it would appear in place when its chunk arrived. An em is
/// wider than any such overhang a reading face draws.
const double scrollInkMarginEm = 1.0;

/// Most tokens one chunk holds.
///
/// A chunk ends at a paragraph or chapter boundary, or here. The cap bounds
/// the one layout the reading path ever does in a frame — a chunk, never the
/// strip — so a book set as a single paragraph costs the same per frame as
/// one set in short ones. A cut falls at a space, where no shaping crosses,
/// so where it lands is invisible.
///
/// Kept small because that frame is one the text is moving in, and at a
/// 165 Hz display its whole budget is about 6 ms. At this cap a join costs
/// about 1 ms on a web build; a smaller cap only means more, cheaper joins,
/// since every token is still laid out once.
const int scrollChunkMaxTokens = 12;

/// Identity of the type style a layout was measured under.
///
/// A record rather than the [TextStyle] itself, so equality is by value and
/// a rebuilt style object with identical fields does not invalidate a
/// perfectly good measurement.
typedef ScrollStyleKey = (String?, double, double);

ScrollStyleKey scrollStyleKeyFor(PresentationConfig config) =>
    (config.fontFamily, config.fontSizePt, config.letterSpacingEm);

/// One chunk, laid out as a single line.
///
/// Measured once, when the strip first reaches it, and shared unchanged by
/// every [ScrollLayout] that holds it after that. The blank after it — a
/// space, a paragraph gap or a chapter gap — is part of [extent] rather than
/// spaces in the string. Inside a chunk the text is shaped as one run, so
/// kerning is what a page of this book would show.
class ScrollSegment {
  final TextPainter painter;

  /// Where this chunk begins, in the strip's coordinate space.
  ///
  /// Fixed when the chunk joins the strip and never moved, so a chunk added
  /// ahead or shed behind leaves every other one exactly where it was drawn.
  final double startX;

  final int firstIndex;

  /// Left edge of each token relative to [startX].
  final List<double> tokenX;

  /// Advance of each token, from its left edge to the next one's, the last
  /// taking the blank after the chunk.
  final List<double> advances;

  /// Distance from [startX] to where the next chunk begins.
  final double extent;

  const ScrollSegment({
    required this.painter,
    required this.startX,
    required this.firstIndex,
    required this.tokenX,
    required this.advances,
    required this.extent,
  });

  int get lastIndex => firstIndex + tokenX.length - 1;

  /// Right edge of the chunk's text, excluding the blank after it.
  double get textEnd => startX + painter.width;

  bool holds(int index) => index >= firstIndex && index <= lastIndex;
}

/// The measured strip: what to paint, and the [TokenRun] the session walks.
class ScrollLayout {
  final List<ScrollSegment> segments;

  /// Handed to `PlaybackSession.run`. Its advances are the distances between
  /// the very token positions [segments] will be painted at.
  final TokenRun run;

  final ScrollStyleKey styleKey;

  /// The space between two tokens under [styleKey], measured once and carried
  /// from strip to strip alongside [TokenRun.meanAdvance]. Null for a strip
  /// with nothing in it, which never measured one.
  final double? spaceWidth;

  const ScrollLayout({
    required this.segments,
    required this.run,
    required this.styleKey,
    this.spaceWidth,
  });

  /// A layout over [segments], which must be contiguous and in order.
  ///
  /// [meanAdvance] is passed rather than derived: it is the basis of the
  /// scroll velocity, so it has to stay put while the strip grows and sheds
  /// chunks — see [coverRun].
  factory ScrollLayout.over(
    List<ScrollSegment> segments, {
    required double meanAdvance,
    required double spaceWidth,
    required ScrollStyleKey styleKey,
  }) => ScrollLayout(
    spaceWidth: spaceWidth,
    segments: List.unmodifiable(segments),
    run: TokenRun(
      firstIndex: segments.first.firstIndex,
      advances: List.unmodifiable([for (final s in segments) ...s.advances]),
      meanAdvance: meanAdvance,
    ),
    styleKey: styleKey,
  );

  int get firstIndex => run.firstIndex;
  int get lastIndex => run.lastIndex;
  bool get isEmpty => segments.isEmpty;

  /// Left edge of the first measured token, in the strip's coordinates.
  /// Negative once chunks have been added behind where the strip began.
  double get leftEdge => segments.isEmpty ? 0 : segments.first.startX;

  /// Right edge of the last measured token's text.
  double get rightEdge => segments.isEmpty ? 0 : segments.last.textEnd;

  /// Left edge of [index] in the strip's coordinate space.
  ///
  /// Falls back to the mean beyond the strip so a painter asked about a
  /// token it does not hold draws off-screen rather than throwing.
  double xOf(int index) {
    final segment = _segmentHolding(index);
    if (segment != null) {
      return segment.startX + segment.tokenX[index - segment.firstIndex];
    }
    return leftEdge + (index - firstIndex) * run.meanAdvance;
  }

  ScrollSegment? _segmentHolding(int index) {
    for (final segment in segments) {
      if (segment.holds(index)) return segment;
    }
    return null;
  }

  void dispose() {
    for (final segment in segments) {
      segment.painter.dispose();
    }
  }
}

/// Pixels of [layout] measured behind [index], from its left edge.
///
/// The anchor only ever moves forward through a token from its left edge,
/// so the viewport's left edge never sits further back than it does at
/// `tokenOffset` zero.
double scrollCoveredBehind(ScrollLayout layout, int index) =>
    layout.xOf(index) - layout.leftEdge;

/// Pixels of [layout] measured ahead of [index], from its far edge.
///
/// The anchor travels up to a whole advance into the token before the index
/// moves — a word, or a word plus a chapter gap — and the viewport's right
/// edge travels with it. Counted from the left edge instead, the strip would
/// run out on screen for the last stretch of every token.
double scrollCoveredAhead(ScrollLayout layout, int index) =>
    layout.rightEdge - (layout.xOf(index) + layout.run.advanceAt(index));

/// Bring [current] up to covering [index], and return it — the same object
/// when nothing had to change.
///
/// Grows the strip a chunk at a time until [aheadPx] is measured past the
/// current token and [behindPx] before it, and sheds a chunk from either end
/// only when what remains still covers its side by [slackPx] more than that,
/// so growing and shedding cannot chase each other. Neither end is grown
/// past the book's own.
///
/// Nothing held is ever measured again. That is the whole of the guarantee
/// against text changing on screen: a chunk is laid out once, before it is
/// in view, and it is drawn from that one layout until it is shed. Only
/// these start the strip over, measuring around [index] from scratch:
///
/// - no strip yet, or [index] outside it (a seek),
/// - a different type style, or
/// - [relayout], for a font that arrived after the strip was measured.
///
/// [TokenRun.meanAdvance] is the basis of the scroll velocity. It is taken
/// from the first strip measured under a style and then carried unchanged —
/// across growth, shedding and seeks — so the text never changes speed
/// because the strip moved. A style change or [relayout] takes a new one.
/// [ScrollLayout.spaceWidth] is carried and retaken the same way.
ScrollLayout coverRun({
  required ScrollLayout? current,
  required List<Token> tokens,
  required int index,
  required TextStyle style,
  required ScrollStyleKey styleKey,
  required Set<int> chapterStarts,
  required bool Function(int) isParagraphEnd,
  required double aheadPx,
  required double behindPx,
  required double slackPx,
  bool relayout = false,
}) {
  if (tokens.isEmpty) {
    if (current != null && current.isEmpty) return current;
    return ScrollLayout(
      segments: const [],
      run: TokenRun.empty,
      styleKey: styleKey,
    );
  }

  final sameStyle =
      current != null && !current.isEmpty && current.styleKey == styleKey;
  final keep =
      sameStyle &&
      !relayout &&
      index >= current.firstIndex &&
      index <= current.lastIndex;

  // The common frame: the strip still covers both sides and has nothing to
  // spare. Answered off the strip as it stands, so a frame that changes
  // nothing allocates nothing.
  if (keep &&
      _settled(current, tokens.length, index, aheadPx, behindPx, slackPx)) {
    return current;
  }

  final chunker = _Chunker(
    tokens: tokens,
    style: style,
    chapterStarts: chapterStarts,
    isParagraphEnd: isParagraphEnd,
    spaceWidth: sameStyle && !relayout ? current.spaceWidth : null,
  );

  final segments = keep
      ? List.of(current.segments)
      : [chunker.forwardFrom(index, startX: 0)];
  final draft = _Draft(segments);
  var changed = !keep;

  while (segments.last.lastIndex < tokens.length - 1 &&
      draft.coveredAhead(index) < aheadPx) {
    final last = segments.last;
    segments.add(
      chunker.forwardFrom(
        last.lastIndex + 1,
        startX: last.startX + last.extent,
      ),
    );
    changed = true;
  }

  while (segments.first.firstIndex > 0 &&
      draft.coveredBehind(index) < behindPx) {
    segments.insert(0, chunker.backwardFrom(segments.first));
    changed = true;
  }

  // Shed only what the far side of the strip can spare: coverage is worked
  // out as it would be *after* dropping, so the loops above cannot want the
  // chunk back on the next frame.
  while (segments.length > 1 &&
      draft.xOf(index) - segments[1].startX >= behindPx + slackPx) {
    segments.removeAt(0);
    changed = true;
  }

  while (segments.length > 1 &&
      segments[segments.length - 2].textEnd - draft.farEdgeOf(index) >=
          aheadPx + slackPx) {
    segments.removeLast();
    changed = true;
  }

  if (!changed) return current!;

  final meanAdvance = sameStyle && !relayout
      ? current.run.meanAdvance
      : _meanOf(segments, chunker.fontSize);

  return ScrollLayout.over(
    segments,
    meanAdvance: meanAdvance,
    spaceWidth: chunker.spaceWidth,
    styleKey: styleKey,
  );
}

/// Whether [layout] covers [index] on both sides and holds nothing it could
/// shed — the tests [coverRun]'s loops make, asked of a finished strip.
bool _settled(
  ScrollLayout layout,
  int tokenCount,
  int index,
  double aheadPx,
  double behindPx,
  double slackPx,
) {
  if (layout.lastIndex < tokenCount - 1 &&
      scrollCoveredAhead(layout, index) < aheadPx) {
    return false;
  }
  if (layout.firstIndex > 0 && scrollCoveredBehind(layout, index) < behindPx) {
    return false;
  }

  final segments = layout.segments;
  if (segments.length < 2) return true;

  final x = layout.xOf(index);
  if (x - segments[1].startX >= behindPx + slackPx) return false;
  final farEdge = x + layout.run.advanceAt(index);
  return segments[segments.length - 2].textEnd - farEdge < aheadPx + slackPx;
}

double _meanOf(List<ScrollSegment> segments, double fontSize) {
  var total = 0.0;
  var count = 0;
  for (final segment in segments) {
    for (final advance in segment.advances) {
      total += advance;
      count++;
    }
  }
  final mean = count == 0 ? 0.0 : total / count;
  return mean > 0 ? mean : fontSize;
}

/// Coverage arithmetic over a strip still being assembled.
extension type _Draft(List<ScrollSegment> segments) {
  ScrollSegment _holding(int index) =>
      segments.firstWhere((s) => s.holds(index));

  double xOf(int index) {
    final segment = _holding(index);
    return segment.startX + segment.tokenX[index - segment.firstIndex];
  }

  double farEdgeOf(int index) {
    final segment = _holding(index);
    final i = index - segment.firstIndex;
    return segment.startX + segment.tokenX[i] + segment.advances[i];
  }

  double coveredAhead(int index) => segments.last.textEnd - farEdgeOf(index);

  double coveredBehind(int index) => xOf(index) - segments.first.startX;
}

/// Lays out chunks under one style.
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
class _Chunker {
  final List<Token> tokens;
  final TextStyle style;
  final Set<int> chapterStarts;
  final bool Function(int) isParagraphEnd;
  final double fontSize;

  _Chunker({
    required this.tokens,
    required this.style,
    required this.chapterStarts,
    required this.isParagraphEnd,
    this._spaceWidth,
  }) : fontSize = style.fontSize ?? 16;

  double? _spaceWidth;

  /// Width of the space between two tokens, measured on first use under a
  /// style and then handed on through [ScrollLayout.spaceWidth].
  ///
  /// Handed on rather than measured per chunker, because a chunker lives for
  /// one call and a chunk joins the strip on a frame the text is moving in:
  /// two more layouts on that frame were a third of what joining cost.
  ///
  /// Measured as a difference rather than by laying out `' '` on its own:
  /// `TextPainter.width` does not count whitespace at the end of a line, so a
  /// lone space measures zero and every token would be drawn touching the
  /// next.
  double get spaceWidth => _spaceWidth ??= () {
    final withSpace = _layout('x x');
    final without = _layout('xx');
    final width = withSpace.width - without.width;
    withSpace.dispose();
    without.dispose();
    return width > 0 ? width : fontSize * 0.25;
  }();

  /// Blank after [index] beyond the space every token has, or zero.
  double _gapAfter(int index) {
    if (chapterStarts.contains(index + 1)) return fontSize * scrollChapterGapEm;
    if (isParagraphEnd(index)) return fontSize * scrollParagraphGapEm;
    return 0;
  }

  bool _endsChunk(int index) =>
      chapterStarts.contains(index + 1) || isParagraphEnd(index);

  /// The chunk beginning at [first], placed at [startX].
  ScrollSegment forwardFrom(int first, {required double startX}) {
    var last = first;
    while (last < tokens.length - 1 &&
        last - first + 1 < scrollChunkMaxTokens &&
        !_endsChunk(last)) {
      last++;
    }
    return _measure(first, last, startX: startX);
  }

  /// The chunk ending just before [next], placed to end where [next] begins.
  ScrollSegment backwardFrom(ScrollSegment next) {
    final last = next.firstIndex - 1;
    var first = last;
    while (first > 0 &&
        last - first + 1 < scrollChunkMaxTokens &&
        !_endsChunk(first - 1)) {
      first--;
    }
    final placed = _measure(first, last, startX: 0);
    return ScrollSegment(
      painter: placed.painter,
      startX: next.startX - placed.extent,
      firstIndex: placed.firstIndex,
      tokenX: placed.tokenX,
      advances: placed.advances,
      extent: placed.extent,
    );
  }

  ScrollSegment _measure(int first, int last, {required double startX}) {
    final buffer = StringBuffer();
    final starts = <int>[];
    for (var i = first; i <= last; i++) {
      if (i > first) buffer.write(' ');
      starts.add(buffer.length);
      buffer.write(tokens[i].text);
    }

    final painter = _layout(buffer.toString());

    // Caret offsets rather than `getBoxesForRange`: a box list can come back
    // empty for a range the shaper folded away, and a caret position is
    // defined for every character index in the string.
    final tokenX = [
      for (final start in starts)
        painter.getOffsetForCaret(TextPosition(offset: start), Rect.zero).dx,
    ];

    // Advance from each token's left edge to the next one's. The last token
    // has no next edge in this chunk, so it takes the rest of the chunk plus
    // the space and whatever the boundary adds.
    final blank = spaceWidth + _gapAfter(last);
    final advances = [
      for (var i = 0; i < tokenX.length - 1; i++) tokenX[i + 1] - tokenX[i],
      painter.width - tokenX.last + blank,
    ];

    return ScrollSegment(
      painter: painter,
      startX: startX,
      firstIndex: first,
      tokenX: tokenX,
      advances: advances,
      extent: painter.width + blank,
    );
  }

  TextPainter _layout(String text) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
}
