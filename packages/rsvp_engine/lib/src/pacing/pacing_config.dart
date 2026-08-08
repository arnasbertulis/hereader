import '../json_coerce.dart';

enum PacingModelKind { constant, lengthScaled, elicited }

class PacingConfig {
  final PacingModelKind kind;
  final double baseWpm;

  final double referenceLetterCount;

  final double lengthScaleStrength;

  final Duration clausePause;
  final Duration sentencePause;
  final Duration paragraphPause;

  final Duration minDisplay;
  final Duration maxDisplay;

  const PacingConfig({
    this.kind = PacingModelKind.constant,
    this.baseWpm = 250,
    this.referenceLetterCount = 5.0,
    this.lengthScaleStrength = 1.0,
    this.clausePause = const Duration(milliseconds: 90),
    this.sentencePause = const Duration(milliseconds: 220),
    this.paragraphPause = const Duration(milliseconds: 400),
    this.minDisplay = const Duration(milliseconds: 40),
    this.maxDisplay = const Duration(milliseconds: 1200),
  }) : assert(baseWpm > 0),
       assert(referenceLetterCount > 0),
       assert(lengthScaleStrength >= 0 && lengthScaleStrength <= 1);

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'baseWpm': baseWpm,
    'referenceLetterCount': referenceLetterCount,
    'lengthScaleStrength': lengthScaleStrength,
    'clausePauseMs': clausePause.inMilliseconds,
    'sentencePauseMs': sentencePause.inMilliseconds,
    'paragraphPauseMs': paragraphPause.inMilliseconds,
    'minDisplayMs': minDisplay.inMilliseconds,
    'maxDisplayMs': maxDisplay.inMilliseconds,
  };

  /// Reads pacing settings written by any build of this package.
  ///
  /// The asserts above hold for values this app constructs. They cannot hold
  /// for values arriving through sync, where the writing device decided what
  /// was in range. Out-of-range numbers move to the nearest bound instead of
  /// throwing, because a throw inside the pull loop loses the event
  /// permanently. See `json_coerce.dart`.
  factory PacingConfig.fromJson(Map<String, dynamic> json) {
    // The constructor's own defaults, read off an instance, so a fallback
    // here cannot drift away from the value it falls back to.
    const fallback = PacingConfig();

    Duration millis(Object? raw, Duration self) =>
        Duration(milliseconds: coerceInt(raw, self.inMilliseconds, min: 0));

    return PacingConfig(
      kind: enumByName(PacingModelKind.values, json['kind'], fallback.kind),
      baseWpm: coerceDouble(json['baseWpm'], fallback.baseWpm, min: 1),
      referenceLetterCount: coerceDouble(
        json['referenceLetterCount'],
        fallback.referenceLetterCount,
        min: 1,
      ),
      lengthScaleStrength: coerceDouble(
        json['lengthScaleStrength'],
        fallback.lengthScaleStrength,
        min: 0,
        max: 1,
      ),
      clausePause: millis(json['clausePauseMs'], fallback.clausePause),
      sentencePause: millis(json['sentencePauseMs'], fallback.sentencePause),
      paragraphPause: millis(json['paragraphPauseMs'], fallback.paragraphPause),
      minDisplay: millis(json['minDisplayMs'], fallback.minDisplay),
      maxDisplay: millis(json['maxDisplayMs'], fallback.maxDisplay),
    );
  }
}
