import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'profile_presentation.dart';
import 'token_run_measure.dart';

/// Supplies time and geometry to a session under continuous scroll.
///
/// `PlaybackSession` stays the only owner of *where the reader is*; this
/// owns *when* and *how wide*. Two objects each holding a notion of the
/// current token is a failure this repo has on record twice, so nothing here
/// keeps an index.
///
/// A [Ticker] rather than the session's own `Timer` chain. That chain
/// schedules each timer when the previous one fires rather than against an
/// absolute clock, and carries a recorded overshoot as an open item; a
/// marquee that is not frame-accurate judders. The session's timer is off in
/// this mode by construction — see `PlaybackSession._scheduleCurrent`.
class ScrollClock {
  final PlaybackSession session;
  final List<Token> tokens;

  /// `TokenizedText.isParagraphEndAt`, passed rather than re-derived, so the
  /// blank drawn after a paragraph and the token the paragraph jump lands on
  /// cannot describe different places.
  final bool Function(int) isParagraphEnd;

  /// Token indices that begin a chapter. Empty for a note or a book with no
  /// table of contents, which then gets paragraph gaps and no invented ones.
  final Set<int> chapterStarts;

  /// The measured window, for the painter.
  ///
  /// A notifier rather than a field on the reader's `State`: a rebuild moves
  /// the window about every forty tokens, and routing it through `setState`
  /// would rebuild the Scaffold, the controls and the chapter panel to shift
  /// some text sideways. The painter listens to this and to the update
  /// stream, and nothing between them is an element.
  final ValueNotifier<ScrollLayout?> layout = ValueNotifier(null);

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  ResolvedPresentation? _presentation;

  /// Longest gap a single tick will move the text by.
  ///
  /// A backgrounded tab, a garbage collection or a slow first frame can hand
  /// back a delta of many frames. Advancing by all of it would jump the
  /// reader forward through text they never saw, which is the same harm the
  /// lifecycle pause exists to prevent, so the motion is capped and the time
  /// is lost instead.
  static const Duration maxTickDelta = Duration(milliseconds: 100);

  ScrollClock({
    required this.session,
    required TickerProvider vsync,
    required this.tokens,
    required this.isParagraphEnd,
    required this.chapterStarts,
  }) {
    _ticker = vsync.createTicker(_onTick);
  }

  @visibleForTesting
  bool get isTicking => _ticker.isActive;

  /// Adopt the presentation the surface is drawing under.
  ///
  /// Call from `didChangeDependencies` and after any profile change — never
  /// from `build`, because this can replace [layout] and marking a painter
  /// dirty mid-build is not something to reason about per frame.
  void applyPresentation(ResolvedPresentation presentation) {
    _presentation = presentation;
    sync();
  }

  /// Bring the window and the ticker into line with the session.
  ///
  /// Cheap and idempotent: called from the session's update listener, which
  /// fires on every state change, and it does nothing at all when the layout
  /// still covers the anchor with room to spare.
  void sync() {
    final presentation = _presentation;
    if (presentation == null) return;

    if (!session.scrolling) {
      _ticker.stop();
      _replace(null);
      return;
    }

    _remeasureIfNeeded(presentation);

    if (session.state == PlaybackState.playing) {
      if (!_ticker.isActive) {
        _lastElapsed = Duration.zero;
        _ticker.start();
      }
    } else {
      _ticker.stop();
    }
  }

  void dispose() {
    _ticker.dispose();
    layout.value?.dispose();
    layout.dispose();
  }

  // ---------------------------------------------------------------------

  void _onTick(Duration elapsed) {
    var delta = elapsed - _lastElapsed;
    _lastElapsed = elapsed;

    if (delta <= Duration.zero) return;
    if (delta > maxTickDelta) delta = maxTickDelta;

    session.tick(delta);

    // Straight off the session rather than waiting for its update to arrive,
    // so the window is never one frame behind the anchor it has to cover.
    final presentation = _presentation;
    if (presentation != null) _remeasureIfNeeded(presentation);
  }

  void _remeasureIfNeeded(ResolvedPresentation presentation) {
    final styleKey = scrollStyleKeyFor(presentation.config);

    if (scrollLayoutIsUsable(
      layout.value,
      index: session.index,
      tokenCount: tokens.length,
      styleKey: styleKey,
    )) {
      return;
    }

    _replace(
      measureRun(
        tokens: tokens,
        index: session.index,
        style: readingTextStyle(presentation),
        styleKey: styleKey,
        chapterStarts: chapterStarts,
        isParagraphEnd: isParagraphEnd,
      ),
    );
  }

  void _replace(ScrollLayout? next) {
    final previous = layout.value;
    if (identical(previous, next)) return;

    // The session walks the same geometry the painter draws, and it takes it
    // before the painter is told, so no frame can be painted against a run
    // the session has not adopted. `PlaybackSession.run` rescales the
    // sub-token offset, which is what keeps the anchor on the same part of
    // the same word when the type size changes.
    if (next != null) session.run = next.run;
    layout.value = next;

    if (previous == null) return;

    // A frame already in flight may still hold the old painters, and a
    // disposed `TextPainter` throws when painted. One frame is enough.
    SchedulerBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }
}
