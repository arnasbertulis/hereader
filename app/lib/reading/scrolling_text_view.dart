import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'profile_presentation.dart';
import 'token_run_measure.dart';

/// The reading surface under [PresentationMode.continuousScroll].
///
/// Draws one unbroken line of the book's text moving right to left at
/// constant velocity, past a marked eye point held at the profile's anchor.
/// The twin of `RsvpView`, and reached the same way: through `ReadingSurface`,
/// so the settings preview and the reader cannot draw different things.
///
/// Takes the *listenable* rather than the value it carries. The painter
/// subscribes to it directly through `CustomPainter(repaint:)`, so this
/// widget is built once per token crossing — about four times a second —
/// while the painter repaints per frame with no element tree work at all.
/// Handing it the value instead would rebuild this subtree sixty times a
/// second for a picture that changes by a few pixels.
class ScrollingTextView extends StatelessWidget {
  final ValueListenable<PlaybackUpdate?> updates;
  final ResolvedPresentation presentation;

  /// The measured window, carrying null before the first measurement.
  ///
  /// A listenable for the same reason [updates] is: the window moves about
  /// once every forty tokens, and rebuilding this subtree for it would put
  /// an element rebuild on the reading path for a change of geometry. The
  /// painter listens to both.
  ///
  /// Measured by the caller rather than here, because the same measurement
  /// is what the session walks: `PlaybackSession.run` and this painter read
  /// one object, so the token under the marker is the token the session says
  /// is current, by construction rather than by agreement.
  final ValueListenable<ScrollLayout?> layout;

  const ScrollingTextView({
    super.key,
    required this.updates,
    required this.presentation,
    required this.layout,
  });

  @override
  Widget build(BuildContext context) {
    final config = presentation.config;

    return ColoredBox(
      color: colorOf(surfaceArgbFor(presentation)),
      child: ClipRect(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: MarqueePainter(
              updates: updates,
              layout: layout,
              config: config,
              // The accent, guarded against the surface it sits on and
              // falling back to the chrome ink where it cannot clear 3:1 —
              // WCAG 1.4.11's bar for a control that is not text. A reader
              // may tint the background until very little separates from
              // it; the readout warns and deliberately does not block, and a
              // caret that cannot be found is worse than none.
              //
              // Measured against `surfaceArgbFor` rather than the progress
              // track, because that is what is behind it. See
              // [readerCaretFor].
              caretColor: readerCaretFor(
                scheme: Theme.of(context).colorScheme,
                presentation: presentation,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the eye-point caret and the moving text.
///
/// Public so a test can assert off its fields rather than off pixels, the
/// way `reader_chrome_test.dart` asserts off the colour functions.
class MarqueePainter extends CustomPainter {
  final ValueListenable<PlaybackUpdate?> updates;
  final ValueListenable<ScrollLayout?> layout;
  final PresentationConfig config;
  final Color caretColor;

  MarqueePainter({
    required this.updates,
    required this.layout,
    required this.config,
    required this.caretColor,
  }) : super(repaint: Listenable.merge([updates, layout]));

  /// Half the line box the text is laid out in, as a multiple of the type
  /// size. `readingTextStyle` sets `height: 1.2`.
  static const double halfLineEm = 0.6;

  /// Caret width, tip to tip of its base, as a multiple of the type size,
  /// before the profile's own scale is applied.
  static const double caretWidthEm = 0.55;

  /// Caret depth, tip to base, as a multiple of the type size, before the
  /// profile's own scale is applied.
  static const double caretHeightEm = 0.42;

  /// Floor on the drawn stroke, so a thin caret stays visible at a small type
  /// size on a low-density screen.
  static const double minCaretStroke = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final anchorX = config.anchorX * size.width;
    final anchorY = config.anchorY * size.height;

    final current = layout.value;
    final update = updates.value;

    // The end of the book clears the surface, caret included. `RsvpView`
    // reaches this for free — the session emits a null token on finishing,
    // and it draws nothing without one — but this painter is driven by an
    // index and a layout rather than by a token, so it would keep drawing
    // the line it stopped on underneath the end-of-book notice. Marking a
    // place in text that is no longer being read is the caret's one job
    // done wrongly, so it goes too.
    if (update?.state == PlaybackState.finished) return;

    _paintCarets(canvas, anchorX, anchorY);

    if (current == null || current.isEmpty || update == null) return;

    // The anchor sits `tokenOffset` pixels into the current token, so the
    // whole run is shifted to put that point under the marker. This is the
    // only place the two are related, and it is the reason nothing here ever
    // hit-tests a box against the anchor to ask which token is current.
    final origin = anchorX - current.xOf(update.index) - update.tokenOffset;

    for (final segment in current.segments) {
      final x = origin + segment.startX;
      if (x > size.width || x + segment.painter.width < 0) continue;
      segment.painter.paint(
        canvas,
        Offset(x, anchorY - segment.painter.height / 2),
      );
    }
  }

  /// The eye point: one or two carets clear of the line, each pointing at it.
  ///
  /// Never over the text. A rule through the words obscures the one word the
  /// reader is trying to read, which is the opposite of what an eye point is
  /// for, and it also reads as an `l` or an `I` at a glance.
  ///
  /// Both placements are the same wedge mirrored, so the tip is always the
  /// end nearest the line and the caret always points at it.
  void _paintCarets(Canvas canvas, double anchorX, double anchorY) {
    for (final tip in caretTips(anchorY)) {
      _paintCaret(canvas, anchorX, tip, pointsDown: tip < anchorY);
    }
  }

  /// Where each caret's tip sits, in the same coordinates [paint] works in.
  ///
  /// Public so placement and clearance can be asserted as numbers rather than
  /// inferred from a rendered picture. One caret per entry, so the length is
  /// also the answer to "how many".
  @visibleForTesting
  List<double> caretTips(double anchorY) {
    final em = config.fontSizePt;
    final clearance = em * halfLineEm + em * config.caretGapEm;

    return switch (config.caretPlacement) {
      CaretPlacement.above => [anchorY - clearance],
      CaretPlacement.below => [anchorY + clearance],
      CaretPlacement.both => [anchorY - clearance, anchorY + clearance],
    };
  }

  /// The wedge for one caret, in the coordinates [paint] works in.
  ///
  /// Public so a test can measure what is drawn rather than assert that a
  /// constant is still the constant it was. Open for a chevron and closed for
  /// either triangle; the outline is the same shape as the solid, so the two
  /// cannot drift apart.
  @visibleForTesting
  Path caretPath(double anchorX, double tipY, {required bool pointsDown}) {
    final em = config.fontSizePt;
    final halfWidth = em * caretWidthEm * config.caretScale / 2;
    final depth = em * caretHeightEm * config.caretScale;

    // The base sits away from the line, whichever side the caret is on.
    final baseY = pointsDown ? tipY - depth : tipY + depth;

    if (config.caretStyle == CaretStyle.chevron) {
      return Path()
        ..moveTo(anchorX - halfWidth, baseY)
        ..lineTo(anchorX, tipY)
        ..lineTo(anchorX + halfWidth, baseY);
    }

    return Path()
      ..moveTo(anchorX, tipY)
      ..lineTo(anchorX - halfWidth, baseY)
      ..lineTo(anchorX + halfWidth, baseY)
      ..close();
  }

  /// Stroke width for an outlined or chevron caret. Nothing for a solid one,
  /// which has no stroke.
  ///
  /// Independent of [PresentationConfig.caretScale] rather than multiplied by
  /// it: the two settings exist separately so a reader can have a large light
  /// marker or a small heavy one, and scaling one by the other would take
  /// that back. Floored so a thin caret stays visible at a small type size.
  @visibleForTesting
  double get caretStroke => (config.fontSizePt * config.caretThicknessEm).clamp(
    minCaretStroke,
    config.fontSizePt,
  );

  void _paintCaret(
    Canvas canvas,
    double anchorX,
    double tipY, {
    required bool pointsDown,
  }) {
    final path = caretPath(anchorX, tipY, pointsDown: pointsDown);

    final paint = Paint()
      ..color = caretColor
      ..isAntiAlias = true;

    canvas.drawPath(path, switch (config.caretStyle) {
      CaretStyle.filled => paint..style = PaintingStyle.fill,
      // A stroked triangle needs a join, or the tip comes to a spike that
      // renders as a stray pixel at a small size.
      CaretStyle.outline =>
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = caretStroke
          ..strokeJoin = StrokeJoin.round,
      CaretStyle.chevron =>
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = caretStroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
    });
  }

  @override
  bool shouldRepaint(MarqueePainter old) =>
      old.layout != layout ||
      old.config != config ||
      old.caretColor != caretColor ||
      old.updates != updates;
}
