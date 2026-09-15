import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:rsvp_engine/rsvp_engine.dart';

import 'profile_presentation.dart';

/// A code-unit `[start, end)` span over a word's grapheme clusters, wide
/// enough to hold a whole letter as the reader sees it — a combining mark or
/// an emoji included — never part of one. Both the ORP rule and the
/// fixation-point rule below return one of these, so the same split paints
/// either (#475, ADR 0035 §4 amendment).
class _HighlightRange {
  const _HighlightRange(this.start, this.end);

  final int start;
  final int end;
}

/// Draws a single token at the profile's anchor point.
///
/// Owns no timing and no state. Give it the latest [PlaybackUpdate] and it
/// renders that frame; during a punctuation gap the update carries a null
/// token and the surface goes blank.
///
/// The one place that decides what reading looks like. The settings preview
/// draws through this rather than painting its own sample, so a profile
/// cannot look one way while it is being configured and another way while it
/// is being read — and, more concretely, so the contrast readout judges the
/// colours this widget puts on screen. It measured a different pair until
/// the preview was folded in here.
///
/// Takes a [ResolvedPresentation], so a profile that follows the app theme
/// arrives with a polarity already chosen. Resolving here instead would put
/// the decision below the contrast readout in settings, which sits beside
/// this widget and measures what it draws: the readout would report the
/// unresolved colours while the reader looked at the resolved ones, which is
/// the disagreement folding the preview in here fixed once already.
class RsvpView extends StatelessWidget {
  final PlaybackUpdate? update;
  final ResolvedPresentation presentation;

  const RsvpView({super.key, required this.update, required this.presentation});

  /// Horizontal breathing room around the word. Named once so the fit
  /// calculation and the Padding it fits inside can't drift apart.
  static const _horizontalPadding = EdgeInsets.symmetric(horizontal: 16);

  /// The letter to highlight for a word that fits. Preference only: no study
  /// behind it. Counts grapheme clusters, not UTF-16 code units, so a
  /// combining mark or an emoji is never split.
  _HighlightRange _orpRange(String word) {
    final clusters = word.characters.toList();
    if (clusters.isEmpty) return const _HighlightRange(0, 0);
    final n = clusters.length;
    final target = n <= 1
        ? 0
        : n <= 5
        ? 1
        : n <= 9
        ? 2
        : 3;
    var start = 0;
    for (var i = 0; i < target; i++) {
      start += clusters[i].length;
    }
    return _HighlightRange(start, start + clusters[target].length);
  }

  /// The letter to highlight for a word still visibly wider than the surface
  /// at the floor font size: the grapheme cluster whose painted box contains
  /// the fixation point, since the ORP rule's letter may already be clipped
  /// off (#475, ADR 0035 §4 amendment). `style` and `textScaler` must match
  /// what the word is actually painted with, so this measurement agrees with
  /// the paint.
  _HighlightRange _fixationRange(
    String word,
    TextStyle style,
    TextScaler textScaler,
    double anchorX,
  ) {
    final clusters = word.characters.toList();
    if (clusters.isEmpty) return const _HighlightRange(0, 0);
    final painter = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final targetX = (anchorX * painter.width).clamp(0.0, painter.width);
    var start = 0;
    for (final cluster in clusters) {
      final end = start + cluster.length;
      final endX = end >= word.length
          ? painter.width
          : painter.getOffsetForCaret(TextPosition(offset: end), Rect.zero).dx;
      if (targetX < endX || end >= word.length) {
        return _HighlightRange(start, end);
      }
      start = end;
    }
    final last = clusters.last;
    return _HighlightRange(word.length - last.length, word.length);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    // Everything below the polarity reads off the config itself. An extension
    // type carries no members of what it wraps, which is what stops an
    // unresolved config reaching a paint call by looking close enough.
    final config = presentation.config;

    final token = update?.token;
    final transition = reduceMotion ? 0 : config.transitionMs;

    // Read once, off the same context the Text/Text.rich below paints
    // ambiently with, and passed to fitFontSizePt so the width it fits to
    // matches what actually gets painted: the reading surface stacks with
    // the platform's own text scaler rather than pinning away from it, the
    // opposite of chromeTextScale's stance (#467, ADR 0035 §4 amendment).
    final textScaler = MediaQuery.textScalerOf(context);

    // Read alongside the text scaler, for the same reason: fitFontSizePt
    // decides overflow-at-the-floor to the same physical-pixel tolerance the
    // paint is judged by (#475, ADR 0035 §4 amendment).
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    // Measured in a LayoutBuilder rather than off MediaQuery's full window
    // size, so the word grows to fill *this widget's* box -- the reader
    // surface or the settings preview, whichever is drawing it -- instead of
    // the settings preview ballooning to the size the reader gets.
    return LayoutBuilder(
      builder: (context, constraints) {
        final filledFontSizePt = scaledFontSizePt(
          config.fontSizePt,
          constraints.maxWidth,
        );

        // Reads off the same padding fact the Padding below is built from:
        // the word never sees the horizontal padding it is drawn inside, so
        // fitting to the full box width would let a fitted word still touch
        // the fitted-to edge.
        final availableTextWidth =
            (constraints.maxWidth - _horizontalPadding.horizontal).clamp(
              0.0,
              double.infinity,
            );

        // Grow-to-fill decides the size a short word gets; scale-to-fit only
        // ever shrinks *this* word further, never past what the profile
        // already allows the reader to choose (ADR 0035 §4).
        final fit = token == null
            ? null
            : fitFontSizePt(
                token.text,
                presentation,
                basePt: filledFontSizePt,
                availableWidth: availableTextWidth,
                textScaler: textScaler,
                devicePixelRatio: devicePixelRatio,
              );
        final fontSizePt = fit?.fontSizePt ?? filledFontSizePt;
        final style = readingTextStyle(presentation, fontSizePt: fontSizePt);

        Widget word;
        if (token == null) {
          // Gap between tokens, or nothing loaded yet. Hold the space so the
          // anchor does not shift.
          word = SizedBox(
            key: const ValueKey('blank'),
            height: fontSizePt * 1.2,
          );
        } else if (config.orpHighlight) {
          final range = (fit?.overflowsAtFloor ?? false)
              ? _fixationRange(token.text, style, textScaler, config.anchorX)
              : _orpRange(token.text);
          word = Text.rich(
            TextSpan(
              children: [
                TextSpan(text: token.text.substring(0, range.start)),
                TextSpan(
                  text: token.text.substring(range.start, range.end),
                  style: TextStyle(color: colorOf(orpArgb)),
                ),
                TextSpan(text: token.text.substring(range.end)),
              ],
            ),
            key: ValueKey('${update!.index}'),
            style: style,
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          );
        } else {
          word = Text(
            token.text,
            key: ValueKey('${update!.index}'),
            style: style,
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          );
        }

        // Every word, fitting or overflowing, gets the same fixed-width clip
        // box so horizontal placement has one writer. Aligning the word
        // inside it at anchorX reproduces the fixation-point formula an
        // intrinsic-width word gets from the outer Align below; when the
        // word is wider than the box, that same formula clips the excess
        // from both ends in proportion to anchorX instead of always losing
        // the end away from the reader's anchor (#468, ADR 0035 §4
        // amendment).
        word = SizedBox(
          width: availableTextWidth,
          child: ClipRect(
            child: OverflowBox(
              maxWidth: double.infinity,
              fit: OverflowBoxFit.deferToChild,
              alignment: Alignment(config.anchorX * 2 - 1, 0),
              child: word,
            ),
          ),
        );

        return ColoredBox(
          color: colorOf(surfaceArgbFor(presentation)),
          child: Align(
            // Anchor fractions map onto Alignment's -1..1 range. Vertical
            // only: the clip box above always fills the width, so anchorX is
            // written there and nowhere else.
            alignment: Alignment(0, config.anchorY * 2 - 1),
            child: Padding(
              padding: _horizontalPadding,
              child: transition == 0
                  ? word
                  : AnimatedSwitcher(
                      duration: Duration(milliseconds: transition),
                      child: word,
                    ),
            ),
          ),
        );
      },
    );
  }
}
