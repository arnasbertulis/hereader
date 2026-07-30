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

  final _updates = StreamController<PlaybackUpdate>.broadcast();

  PlaybackSession({
    required this.tokens,
    required ReadingProfile profile,
    int startIndex = 0,
  })  : _profile = profile,
        _model = PacingModel.of(profile.pacing.kind) {
    _index = startIndex.clamp(0, tokens.isEmpty ? 0 : tokens.length - 1);
    if (tokens.isEmpty) _state = PlaybackState.finished;
  }

  Stream<PlaybackUpdate> get updates => _updates.stream;

  PlaybackState get state => _state;
  int get index => _index;

  Token? get currentToken =>
      _state == PlaybackState.finished || tokens.isEmpty ? null : tokens[_index];

  /// Character offset of the current token within its source block. Combine
  /// with bookId, blockId and parserVersion to form a stored locator.
  int? get charOffset => currentToken?.charOffset;

  ReadingProfile get profile => _profile;

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

    if (_state == PlaybackState.paused) {
      _index = (_index - _profile.rewindWords).clamp(0, tokens.length - 1);
    }

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
    _updates.add(PlaybackUpdate(
      state: _state,
      index: _index,
      token: _state == PlaybackState.finished || _inGap ? null : tokens[_index],
      inGap: _inGap,
    ));
  }
}
