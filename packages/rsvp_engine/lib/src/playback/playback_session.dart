import 'dart:async';

import '../pacing/pacing_decision.dart';
import '../pacing/pacing_model.dart';
import '../profile/profile.dart';
import '../token.dart';

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

  const PlaybackUpdate({
    required this.state,
    required this.index,
    required this.token,
    this.inGap = false,
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
  );

  /// Swap the profile mid-session. Takes effect from the next token, or
  /// immediately if the session is not currently timing one.
  set profile(ReadingProfile next) {
    _profile = next;
    _model = PacingModel.of(next.pacing.kind);

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

    if (_state == PlaybackState.paused && !_resumeHere) {
      _index = (_index - _profile.rewindWords).clamp(0, tokens.length - 1);
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
    _resumeHere = true;

    if (_state == PlaybackState.awaitingAdvance) {
      _scheduleCurrent();
      return;
    }

    _setState(PlaybackState.paused);
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

  void _scheduleCurrent() {
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
      ),
    );
  }
}
