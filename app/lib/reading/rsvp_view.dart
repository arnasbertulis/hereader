import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// Draws a single token at the profile's anchor point.
///
/// Owns no timing and no state. Give it the latest [PlaybackUpdate] and it
/// renders that frame; during a punctuation gap the update carries a null
/// token and the surface goes blank.
class RsvpView extends StatelessWidget {
  final PlaybackUpdate? update;
  final PresentationConfig presentation;

  const RsvpView({super.key, required this.update, required this.presentation});

  Color get _foreground => presentation.polarity == Polarity.lightOnDark
      ? const Color(0xFFF2F2F2)
      : const Color(0xFF0D0D0D);

  Color get _background {
    if (presentation.tintArgb != null) return Color(presentation.tintArgb!);
    return presentation.polarity == Polarity.lightOnDark
        ? const Color(0xFF080808)
        : const Color(0xFFFCFCFC);
  }

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

    final style = TextStyle(
      fontFamily: presentation.fontFamily,
      fontSize: presentation.fontSizePt,
      letterSpacing: presentation.fontSizePt * presentation.letterSpacingEm,
      height: 1.2,
      color: _foreground,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final token = update?.token;

    Widget word;
    if (token == null) {
      // Gap between tokens, or nothing loaded yet. Hold the space so the
      // anchor does not shift.
      word = SizedBox(
        key: const ValueKey('blank'),
        height: presentation.fontSizePt * 1.2,
      );
    } else if (presentation.orpHighlight) {
      final i = _orpIndex(token.text);
      word = Text.rich(
        TextSpan(
          children: [
            TextSpan(text: token.text.substring(0, i)),
            TextSpan(
              text: token.text[i],
              style: const TextStyle(color: Color(0xFFD23B2E)),
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

    final transition = reduceMotion ? 0 : presentation.transitionMs;

    return ColoredBox(
      color: _background,
      child: Align(
        // Anchor fractions map onto Alignment's -1..1 range.
        alignment: Alignment(
          presentation.anchorX * 2 - 1,
          presentation.anchorY * 2 - 1,
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
