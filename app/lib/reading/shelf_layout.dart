import 'package:flutter/material.dart';

/// ADR 0031's Base — the type size every chrome role is a multiple of. The
/// column-drop threshold below is calibrated as a ratio of it, so raising the
/// Base moves the threshold with it instead of leaving it pointed at a size
/// that no longer exists in the type scale.
const double kShelfBaseTextSize = 16.0;

/// One line of a shelf tile's text block, for [measuredShelfTextBlockHeight].
///
/// [sampleTexts] holds the line's worst-case text — the longest content the
/// line can actually carry, since only its wrapped height matters, never its
/// glyphs. When a line has more than one candidate (for example a shelf's set
/// of status words), the tallest of them wins, the same way the tallest of
/// several possible wrapped lines would.
@immutable
class ShelfTextLine {
  const ShelfTextLine({
    required this.sampleTexts,
    required this.style,
    this.maxLines,
    this.gapBefore = 0,
  });

  /// The candidate strings this line can hold; the tallest layout wins.
  final List<String> sampleTexts;

  /// The role this line is painted in. Its resolved font size is what makes
  /// the measurement track both Text size (baked into the style already) and
  /// the platform's own text scale (applied by the [TextScaler] passed to
  /// [measuredShelfTextBlockHeight]).
  final TextStyle? style;

  /// How many lines this text is allowed to wrap onto, or `null` for
  /// unlimited — matches [TextPainter.maxLines].
  final int? maxLines;

  /// Space above this line, in unscaled logical pixels — scaled the same way
  /// the text itself is, so the gap grows with Text size too.
  final double gapBefore;
}

/// The height of a shelf tile's text block: every [line] laid out at
/// [tileWidth] under [scaler], stacked in order.
///
/// Generalises what was `library_screen.dart`'s `_measuredTextBlockHeight` —
/// every shelf passes its own lines (style, line cap, sample text) instead of
/// the Library's set being hard-coded here.
double measuredShelfTextBlockHeight(
  TextScaler scaler,
  double tileWidth,
  List<ShelfTextLine> lines,
) {
  var height = 0.0;
  for (final line in lines) {
    height += scaler.scale(line.gapBefore);

    var lineHeight = 0.0;
    for (final sample in line.sampleTexts) {
      final painter = TextPainter(
        text: TextSpan(text: sample, style: line.style),
        textScaler: scaler,
        textDirection: TextDirection.ltr,
        maxLines: line.maxLines,
      )..layout(maxWidth: tileWidth);
      if (painter.height > lineHeight) lineHeight = painter.height;
    }
    height += lineHeight;
  }
  return height;
}

/// Whether a shelf should drop a column, from the *effective* text size —
/// the platform's text scale combined with the reader's Text size — rather
/// than either alone.
///
/// Reads the threshold off [context]'s own `bodyMedium` size rather than a
/// literal: the trigger point (scaled body text past ~1.29x its Base) is
/// unchanged from before Text size existed, but the size it is applied to is
/// no longer a literal that predates ADR 0031's 16px Base.
bool shelfShouldDropColumn(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  final bodyMediumSize =
      Theme.of(context).textTheme.bodyMedium?.fontSize ?? kShelfBaseTextSize;
  return scaler.scale(bodyMediumSize) > kShelfBaseTextSize * (18 / 14);
}
