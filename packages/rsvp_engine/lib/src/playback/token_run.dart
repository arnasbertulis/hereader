/// Pixel geometry for a window of tokens.
///
/// This package measures nothing and imports no Flutter, so under continuous
/// scroll it is *handed* the geometry it needs: how wide each token is on the
/// screen it is being drawn on, including the gap that follows it.
///
/// A window, not the book. Laying out a whole book to scroll it would cost a
/// measurement pass proportional to its length on the one platform where
/// `compute()` does not offload; ADR 0025 rejects it. Tokens outside the
/// window fall back to [meanAdvance], which is exact enough for a scrub that
/// travels further than the reader can see.
///
/// Immutable and comparable by construction: the renderer builds a new one
/// when the window moves or the type style changes, and hands it to
/// `PlaybackSession.run`, which rescales the sub-token offset so the anchor
/// stays on the same part of the same word.
class TokenRun {
  /// Token index that [advances] starts at.
  final int firstIndex;

  /// Advance in logical pixels per token, from this token's left edge to the
  /// next one's — so it includes the trailing space, and any extra width a
  /// paragraph or chapter boundary adds after it.
  final List<double> advances;

  /// What a token outside the window is assumed to cost.
  ///
  /// Also the basis of the scroll velocity, which is why it is carried rather
  /// than derived on demand: `(baseWpm / 60) * meanAdvance` is the pixels per
  /// second that makes the marquee deliver `baseWpm` words a minute past the
  /// anchor. It is an average and it drifts with the book and the font, the
  /// same caveat `PacingConfig.referenceLetterCount` already carries.
  final double meanAdvance;

  const TokenRun({
    required this.firstIndex,
    required this.advances,
    required this.meanAdvance,
  }) : assert(firstIndex >= 0),
       assert(meanAdvance > 0);

  /// Geometry for a session nothing has measured for yet.
  ///
  /// [meanAdvance] is 1 rather than 0 so that arithmetic dividing by an
  /// advance is safe before the first frame has been laid out. Nothing is
  /// drawn from it: a session holding this has an empty window, so every
  /// lookup returns the fallback and the reader sees whatever the renderer
  /// paints on its first pass, which is the pass that replaces it.
  static const TokenRun empty = TokenRun(
    firstIndex: 0,
    advances: <double>[],
    meanAdvance: 1,
  );

  /// Last token this run measures, or one before [firstIndex] when empty.
  int get lastIndex => firstIndex + advances.length - 1;

  bool contains(int index) => index >= firstIndex && index <= lastIndex;

  /// Width of [index], measured if it is in the window and averaged if not.
  ///
  /// Never returns zero, so a caller walking a distance by repeated
  /// subtraction cannot loop forever.
  double advanceAt(int index) {
    if (!contains(index)) return meanAdvance;
    final advance = advances[index - firstIndex];
    return advance > 0 ? advance : meanAdvance;
  }
}
