import '../token.dart';
import 'pacing_config.dart';
import 'pacing_decision.dart';

abstract class PacingModel {
  const PacingModel();

  PacingDecision decide(Token token, PacingConfig config);

  factory PacingModel.of(PacingModelKind kind) => switch (kind) {
    PacingModelKind.constant => const ConstantPacing(),
    PacingModelKind.lengthScaled => const LengthScaledPacing(),
    PacingModelKind.elicited => const ElicitedPacing(),
  };
}

Duration _baseDuration(PacingConfig c) =>
    Duration(microseconds: (60000000 / c.baseWpm).round());

Duration _clamp(Duration d, PacingConfig c) =>
    d < c.minDisplay ? c.minDisplay : (d > c.maxDisplay ? c.maxDisplay : d);

Duration _pauseFor(Token t, PacingConfig c) => switch (t.pauseAfter) {
  PauseAfter.none => Duration.zero,
  PauseAfter.clause => c.clausePause,
  PauseAfter.sentence => c.sentencePause,
  PauseAfter.paragraph => c.paragraphPause,
};

/// How long a word of reference length is held, before any punctuation
/// pause.
///
/// Null under elicited pacing, where a word has no duration at all and waits
/// for the reader instead — the same distinction `PacingDecision` draws
/// between `Hold` and `AwaitAdvance` (ADR 0003).
///
/// Length-scaled pacing gives the same answer as constant, because a word of
/// exactly `referenceLetterCount` letters scales by one. It is therefore a
/// typical hold rather than a guaranteed one: shorter words are held for
/// less.
///
/// Public because the settings screen has to say when another setting
/// outlasts a word, and that is duration arithmetic rather than English.
Duration? referenceDisplay(PacingConfig config) =>
    config.kind == PacingModelKind.elicited
    ? null
    : _clamp(_baseDuration(config), config);

class ConstantPacing extends PacingModel {
  const ConstantPacing();

  @override
  PacingDecision decide(Token token, PacingConfig config) => Hold(
    _clamp(_baseDuration(config), config),
    pauseAfter: _pauseFor(token, config),
  );
}

class LengthScaledPacing extends PacingModel {
  const LengthScaledPacing();

  @override
  PacingDecision decide(Token token, PacingConfig config) {
    final ratio = token.letterCount / config.referenceLetterCount;
    final factor = 1 + config.lengthScaleStrength * (ratio - 1);
    final scaled = Duration(
      microseconds: (_baseDuration(config).inMicroseconds * factor).round(),
    );
    return Hold(_clamp(scaled, config), pauseAfter: _pauseFor(token, config));
  }
}

class ElicitedPacing extends PacingModel {
  const ElicitedPacing();

  @override
  PacingDecision decide(Token token, PacingConfig config) =>
      const AwaitAdvance();
}
