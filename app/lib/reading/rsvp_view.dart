import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'profile_presentation.dart';

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

  /// Index of the letter to highlight. Preference only: no study behind it.
  int _orpIndex(String word) {
    final n = word.length;
    if (n <= 1) return 0;
    if (n <= 5) return 1;
    if (n <= 9) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    // Everything below the polarity reads off the config itself. An extension
    // type carries no members of what it wraps, which is what stops an
    // unresolved config reaching a paint call by looking close enough.
    final config = presentation.config;

    final style = TextStyle(
      fontFamily: config.fontFamily,
      fontSize: config.fontSizePt,
      letterSpacing: config.fontSizePt * config.letterSpacingEm,
      height: 1.2,
      color: colorOf(inkArgbFor(presentation.polarity)),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final token = update?.token;

    Widget word;
    if (token == null) {
      // Gap between tokens, or nothing loaded yet. Hold the space so the
      // anchor does not shift.
      word = SizedBox(
        key: const ValueKey('blank'),
        height: config.fontSizePt * 1.2,
      );
    } else if (config.orpHighlight) {
      final i = _orpIndex(token.text);
      word = Text.rich(
        TextSpan(
          children: [
            TextSpan(text: token.text.substring(0, i)),
            TextSpan(
              text: token.text[i],
              style: TextStyle(color: colorOf(orpArgb)),
            ),
            TextSpan(text: token.text.substring(i + 1)),
          ],
        ),
        key: ValueKey('${update!.index}'),
        style: style,
        textAlign: TextAlign.center,
      );
    } else {
      word = Text(
        token.text,
        key: ValueKey('${update!.index}'),
        style: style,
        textAlign: TextAlign.center,
      );
    }

    final transition = reduceMotion ? 0 : config.transitionMs;

    return ColoredBox(
      color: colorOf(surfaceArgbFor(presentation)),
      child: Align(
        // Anchor fractions map onto Alignment's -1..1 range.
        alignment: Alignment(
          config.anchorX * 2 - 1,
          config.anchorY * 2 - 1,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: transition == 0
              ? word
              : AnimatedSwitcher(
                  duration: Duration(milliseconds: transition),
                  child: word,
                ),
        ),
      ),
    );
  }
}
