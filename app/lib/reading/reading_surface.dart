import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'profile_presentation.dart';
import 'rsvp_view.dart';
import 'scrolling_text_view.dart';
import 'token_run_measure.dart';

/// The one place that decides which surface a profile draws.
///
/// `RsvpView`'s doc comment records why the settings preview draws through
/// the real surface rather than painting its own sample: the contrast readout
/// sits beside it and measures what it draws, and it measured a pair the app
/// never put on screen until the preview was folded in. A second surface
/// reopens that hole one level up — the preview could pick one and the reader
/// the other — so the choice is made here and both call it. A `switch (mode)`
/// in the reader and another in the editor would be two functions computing
/// one figure.
///
/// The switch is exhaustive with no `default`, so a fourth [PresentationMode]
/// is a compile error at the one place that has to handle it. Same discipline
/// ADR 0003 chose for `PacingDecision`.
class ReadingSurface extends StatelessWidget {
  final ValueListenable<PlaybackUpdate?> updates;
  final ResolvedPresentation presentation;

  /// The measured window, under continuous scroll only. Carries null under
  /// the other modes, and before the first measurement.
  final ValueListenable<ScrollLayout?> layout;

  const ReadingSurface({
    super.key,
    required this.updates,
    required this.presentation,
    required this.layout,
  });

  @override
  Widget build(BuildContext context) => switch (presentation.config.mode) {
    // `shiftingWindow` is not built. It draws the fixed anchor rather than
    // nothing, because a profile carrying it — from a later build, over the
    // wire — should read as a book rather than as a blank screen.
    PresentationMode.fixedSingle ||
    PresentationMode.shiftingWindow => ValueListenableBuilder<PlaybackUpdate?>(
      valueListenable: updates,
      builder: (_, update, _) =>
          RsvpView(update: update, presentation: presentation),
    ),

    // No builder: the painter subscribes to `updates` itself, so the element
    // tree is untouched between token crossings. See [ScrollingTextView].
    PresentationMode.continuousScroll => ScrollingTextView(
      updates: updates,
      presentation: presentation,
      layout: layout,
    ),
  };
}
