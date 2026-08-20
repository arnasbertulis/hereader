import 'dart:async';

import '../pacing/pacing_decision.dart';
import '../pacing/pacing_model.dart';
import '../profile/profile.dart';
import '../token.dart';
import 'token_run.dart';

enum PlaybackState {
  idle,

  /// Advancing on a timer.
  playing,

  /// Stopped by the reader. Resuming applies [ReadingProfile.rewindWords].
  paused,

  /// Waiting for the reader to advance. This is active reading under an
  /// elicited pacing model, not a pause, so no rewind applies.
  awaitingAdvance,

  /// Past the last token. Terminal until [PlaybackSession.seekToIndex].
  finished,
}

/// A snapshot of what the renderer should show.
class PlaybackUpdate {
  final PlaybackState state;
  final int index;

  /// Null while the anchor is blank between tokens, and when finished.
  final Token? token;

  /// True during the pause that follows punctuation.
  final bool inGap;

  /// How far past the left edge of token [index] the anchor sits, in logical
  /// pixels, under [PresentationMode.continuousScroll]. Always 0 otherwise.
  ///
  /// The renderer draws token [index] with its left edge at
  /// `anchor - tokenOffset`, which is what makes "the token crossing the
  /// anchor" *be* [index] by construction. Anything that hit-tests a laid-out
  /// box against the anchor to answer that question instead is a second
  /// notion of the current token, and they will disagree.
  final double tokenOffset;

  const PlaybackUpdate({
    required this.state,
    required this.index,
    required this.token,
    this.inGap = false,
    this.tokenOffset = 0,
  });
}

/// Drives a token list according to a [ReadingProfile].
///
/// Owns no rendering and no persistence. Emits [PlaybackUpdate]s; the caller
/// draws them and, separately, saves `token.charOffset` as a locator.
///
/// Uses [Timer] directly rather than an injected clock. Tests wrap calls in
/// `fakeAsync`, which replaces the Zone's timer factory, so a session at
/// 250 wpm can be stepped through a whole paragraph in microseconds.
class PlaybackSession {
  final List<Token> tokens;

  ReadingProfile _profile;
  PacingModel _model;

  int _index = 0;
  PlaybackState _state = PlaybackState.idle;
  bool _inGap = false;
  Timer? _timer;

  /// Logical pixels into token [_index]'s own advance. Scroll mode only, and
  /// never persisted: the locator format is token-granular (ADR 0002), so a
  /// saved position resumes at the token's leading edge rather than partway
  /// through it. At most one word, and cheaper than a schema, a wire and a
  /// server change to buy back.
  double _offset = 0;

  /// Screen geometry, supplied by the renderer. See [run].
  TokenRun _run = TokenRun.empty;

  /// Set by [stopAt] and spent by the next [play]. See [stopAt] for why.
  bool _resumeHere = false;

  final _updates = StreamController<PlaybackUpdate>.broadcast();

  PlaybackSession({
    required this.tokens,
    required ReadingProfile profile,
    int startIndex = 0,
  }) : _profile = profile,
       _model = PacingModel.of(profile.pacing.kind) {
    _index = startIndex.clamp(0, tokens.isEmpty ? 0 : tokens.length - 1);
    if (tokens.isEmpty) _state = PlaybackState.finished;
  }

  Stream<PlaybackUpdate> get updates => _updates.stream;

  PlaybackState get state => _state;
  int get index => _index;

  Token? get currentToken => _state == PlaybackState.finished || tokens.isEmpty
      ? null
      : tokens[_index];

  /// Character offset of the current token within its source block. Combine
  /// with bookId, blockId and parserVersion to form a stored locator.
  int? get charOffset => currentToken?.charOffset;

  ReadingProfile get profile => _profile;

  /// Whether this session is under continuous scroll.
  ///
  /// Derived from the profile rather than fixed at construction, so
  /// [profile]`=` switches presentation mid-read with nothing else to keep in
  /// step. One owner of the question.
  bool get scrolling =>
      _profile.presentation.mode == PresentationMode.continuousScroll;

  /// Logical pixels into the current token. See [PlaybackUpdate.tokenOffset].
  double get tokenOffset => _offset;

  /// Pixels per second the text moves at under continuous scroll.
  ///
  /// `baseWpm` is the only source; there is no separate scroll speed field
  /// and nothing new on the wire. Note that seconds per token is
  /// `meanAdvance / velocity` = `60 / baseWpm`, so the mean width divides out
  /// of any time estimate and `remainingReadingTime` still answers it.
  double get scrollVelocity =>
      (_profile.pacing.baseWpm / 60) * _run.meanAdvance;

  /// Screen geometry for the tokens around the anchor.
  ///
  /// Setting it rescales [_offset] so the anchor holds the same fraction of
  /// the same word. Without that, dragging the type-size slider would walk
  /// the text sideways under the marker on every frame of the drag. Done here
  /// rather than in the renderer because the session owns the offset, so the
  /// session owns what happens to it when the geometry underneath changes.
  TokenRun get run => _run;

  set run(TokenRun next) {
    final was = _run.advanceAt(_index);
    final fraction = was > 0 ? _offset / was : 0.0;
    _run = next;
    _offset = fraction * next.advanceAt(_index);
  }

  /// The frame a renderer should be showing right now.
  ///
  /// [updates] carries changes, and a session that has not been touched has
  /// not changed, so nothing on the stream describes the state it opens in.
  /// A broadcast controller also has no listeners at construction time, so
  /// emitting from the constructor would not help.
  ///
  /// Without this a screen renders blank until the reader does something.
  /// That is what a book resumed from a stored position looked like on open:
  /// an empty reading surface with the word sitting one tap away.
  ///
  /// Mirrors what [_emit] would produce, including blanking the anchor during
  /// a punctuation gap, so seeding a renderer with this and then listening
  /// cannot show two different things for one state.
  PlaybackUpdate get current => PlaybackUpdate(
    state: _state,
    index: _index,
    token: _inGap ? null : currentToken,
    inGap: _inGap,
    tokenOffset: _offset,
  );

  /// Swap the profile mid-session. Takes effect from the next token, or
  /// immediately if the session is not currently timing one.
  set profile(ReadingProfile next) {
    final wasScrolling = scrolling;
    _profile = next;
    _model = PacingModel.of(next.pacing.kind);

    // Leaving scroll mode: the fixed anchor has no sub-token position, and a
    // stale one would offset the first laid-out token if scroll came back.
    if (wasScrolling && !scrolling) _offset = 0;

    if (_state == PlaybackState.playing ||
        _state == PlaybackState.awaitingAdvance) {
      _timer?.cancel();
      _inGap = false;
      _scheduleCurrent();
    }
  }

  void play() {
    if (tokens.isEmpty || _state == PlaybackState.playing) return;

    if (_state == PlaybackState.finished) return;

    // A rewind of no words is not a move, so it must not zero [_offset]
    // either. Under continuous scroll that would snap the reader back to the
    // leading edge of the word they stopped in, which is the one thing a
    // rewind of none promises not to do.
    if (_state == PlaybackState.paused &&
        !_resumeHere &&
        _profile.rewindWords > 0) {
      _index = (_index - _profile.rewindWords).clamp(0, tokens.length - 1);
      _offset = 0;
    }

    // Spent whether or not it applied, so it describes the last thing the
    // reader did rather than accumulating across resumes.
    _resumeHere = false;

    _inGap = false;
    _scheduleCurrent();
  }

  void pause() {
    if (_state != PlaybackState.playing &&
        _state != PlaybackState.awaitingAdvance) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    _inGap = false;

    // [_offset] is deliberately kept. Under continuous scroll the reader's
    // finger landing pauses first and drags second, so zeroing it here would
    // snap the text back by up to a word before the drag had begun.

    // A pause is not a place the reader picked, so it re-arms the rewind even
    // if a [stopAt] put them here first. Otherwise stepping once and then
    // reading for an hour would still suppress the rewind on the pause after
    // it, an hour later, for a reason nobody could see.
    _resumeHere = false;

    _setState(PlaybackState.paused);
  }

  /// Move to the next token. Called by the reader under elicited pacing, and
  /// usable as a manual skip while playing.
  void advance() {
    if (_state == PlaybackState.finished || tokens.isEmpty) return;

    _timer?.cancel();
    _inGap = false;

    if (_index >= tokens.length - 1) {
      _finish();
      return;
    }

    _index++;
    _offset = 0;

    if (_state == PlaybackState.paused) {
      _emit();
      return;
    }
    _scheduleCurrent();
  }

  /// Step back without treating it as a resume, so [ReadingProfile.rewindWords]
  /// does not compound.
  void rewind([int count = 1]) {
    if (tokens.isEmpty) return;

    _timer?.cancel();
    _inGap = false;

    final wasFinished = _state == PlaybackState.finished;
    _index = (_index - count).clamp(0, tokens.length - 1);
    _offset = 0;

    if (wasFinished || _state == PlaybackState.paused) {
      if (wasFinished) _setState(PlaybackState.paused);
      _emit();
      return;
    }
    _scheduleCurrent();
  }

  void seekToIndex(int target) {
    if (tokens.isEmpty) return;

    _timer?.cancel();
    _inGap = false;
    _index = target.clamp(0, tokens.length - 1);
    _offset = 0;

    if (_state == PlaybackState.playing) {
      _scheduleCurrent();
    } else {
      _setState(PlaybackState.paused);
      _emit();
    }
  }

  /// Move to [target] and stop there, as a place the reader chose.
  ///
  /// Unlike [pause], resuming from here does not apply
  /// [ReadingProfile.rewindWords]. That field exists so a reader coming back
  /// to a book re-enters the sentence with some context; a reader who has just
  /// stepped onto a particular word does not want to be moved off it, and
  /// under a tap zone the two land one after the other on every single step.
  ///
  /// The suppression lasts exactly one [play] and any [pause] clears it.
  ///
  /// [PlaybackState.awaitingAdvance] is not turned into a pause. It is active
  /// reading under an elicited pacing model rather than a stop, so a step
  /// re-schedules and the reader keeps the advance they were using. Every
  /// other state stops.
  void stopAt(int target) {
    if (tokens.isEmpty) return;

    _timer?.cancel();
    _inGap = false;
    _index = target.clamp(0, tokens.length - 1);
    _offset = 0;
    _resumeHere = true;

    if (_state == PlaybackState.awaitingAdvance) {
      _scheduleCurrent();
      return;
    }

    _setState(PlaybackState.paused);
  }

  /// Stop exactly where the anchor already is, as a place the reader chose.
  ///
  /// [stopAt] without the move: same one-shot rewind suppression, same
  /// treatment of [PlaybackState.awaitingAdvance], but the index and the
  /// sub-token offset are left alone.
  ///
  /// This is what a finger lifting off a scrub calls. Routing that through
  /// [stopAt] instead would zero the offset and snap the text by up to a
  /// word at the moment of release — the same insult in a different unit as
  /// a rewind undoing a step the reader just made.
  void stopHere() {
    if (tokens.isEmpty) return;

    _timer?.cancel();
    _inGap = false;
    _resumeHere = true;

    if (_state == PlaybackState.awaitingAdvance) {
      _scheduleCurrent();
      return;
    }

    _setState(PlaybackState.paused);
  }

  /// Advance the scroll by one frame's worth of motion.
  ///
  /// A no-op unless [scrolling] and actually playing, so a stray tick from a
  /// ticker that has not stopped yet cannot move a paused session.
  ///
  /// The renderer supplies the *time*; this stays the only owner of the
  /// position. See ADR 0025 for why the timer chain does not drive this: it
  /// is scheduled from the previous timer firing rather than against an
  /// absolute clock, and a marquee that is not frame-accurate judders.
  void tick(Duration elapsed) {
    if (!scrolling || _state != PlaybackState.playing) return;
    if (tokens.isEmpty || elapsed <= Duration.zero) return;

    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (_walk(scrollVelocity * seconds)) {
      _finish();
    } else {
      _emit();
    }
  }

  /// Move the anchor [dx] logical pixels through the text, either sign.
  ///
  /// Positive is forward, so a finger moving left drags the text left and the
  /// reader forward. Does not touch [_state] and does not arm the rewind
  /// suppression: a drag is many of these and the *release* is the moment the
  /// reader chose, so [stopHere] carries that.
  ///
  /// Shares [_walk] with [tick] on purpose. Two walks over the same geometry
  /// is how a drag and a playback come to disagree about where a token ends.
  void scrubBy(double dx) {
    if (!scrolling || tokens.isEmpty) return;

    _timer?.cancel();
    _inGap = false;

    final hitEnd = _walk(dx);
    if (_state == PlaybackState.finished && !hitEnd) {
      // Scrubbing back off the end is a way out of a terminal state that
      // does not go through seekToIndex, so say so rather than emitting a
      // finished update carrying a token.
      _state = PlaybackState.paused;
    }
    _emit();
  }

  /// Resume from a stored locator. Lands on the token containing [offset], or
  /// the last one starting before it.
  ///
  /// Offsets rather than word indices are what make this survive a tokenizer
  /// change; see ADR 0002.
  void seekToCharOffset(int offset) {
    if (tokens.isEmpty) return;

    var target = 0;
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i].charOffset <= offset) {
        target = i;
      } else {
        break;
      }
    }
    seekToIndex(target);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _updates.close();
  }

  // ---------------------------------------------------------------------

  /// Move `(_index, _offset)` by [dx] pixels. Returns true if it ran off the
  /// end of the text.
  ///
  /// Repeated subtraction rather than a division: nothing here is
  /// integer-width sensitive, and keeping integer truncation out of the
  /// arithmetic entirely is cheaper than reasoning about whether it is
  /// (ADR 0009). [TokenRun.advanceAt] never returns zero, so neither loop can
  /// spin.
  bool _walk(double dx) {
    _offset += dx;

    var advance = _run.advanceAt(_index);
    while (_offset >= advance) {
      if (_index >= tokens.length - 1) {
        _offset = 0;
        return true;
      }
      _offset -= advance;
      _index++;
      advance = _run.advanceAt(_index);
    }

    while (_offset < 0) {
      if (_index == 0) {
        _offset = 0;
        break;
      }
      _index--;
      _offset += _run.advanceAt(_index);
    }

    return false;
  }

  void _scheduleCurrent() {
    // Continuous scroll carries its own clock, so the timer chain must never
    // arm. Gated in the callee rather than at the six methods that call it,
    // because six call sites is six chances to miss one; here every caller is
    // correct by construction and `_timer?.cancel()` is harmlessly a no-op
    // throughout.
    //
    // [_model] is therefore never consulted under scroll, which is the whole
    // of "scroll outranks elicited pacing": `AwaitAdvance` is unreachable
    // rather than handled. There is no branch for it, deliberately.
    if (scrolling) {
      _setState(PlaybackState.playing);
      return;
    }

    final decision = _model.decide(tokens[_index], _profile.pacing);

    switch (decision) {
      case AwaitAdvance():
        _setState(PlaybackState.awaitingAdvance);

      case Hold(:final display, :final pauseAfter):
        _setState(PlaybackState.playing);
        _timer = Timer(display, () {
          if (pauseAfter > Duration.zero) {
            _inGap = true;
            _emit();
            _timer = Timer(pauseAfter, _step);
          } else {
            _step();
          }
        });
    }
  }

  void _step() {
    _inGap = false;
    if (_index >= tokens.length - 1) {
      _finish();
      return;
    }
    _index++;
    _scheduleCurrent();
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    _inGap = false;
    _offset = 0;
    _setState(PlaybackState.finished);
  }

  void _setState(PlaybackState next) {
    _state = next;
    _emit();
  }

  void _emit() {
    if (_updates.isClosed) return;
    _updates.add(
      PlaybackUpdate(
        state: _state,
        index: _index,
        token: _state == PlaybackState.finished || _inGap
            ? null
            : tokens[_index],
        inGap: _inGap,
        tokenOffset: _offset,
      ),
    );
  }
}
