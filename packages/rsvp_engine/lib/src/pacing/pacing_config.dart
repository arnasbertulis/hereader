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

  factory PacingConfig.fromJson(Map<String, dynamic> json) => PacingConfig(
        kind: PacingModelKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => PacingModelKind.constant,
        ),
        baseWpm: (json['baseWpm'] as num?)?.toDouble() ?? 250,
        referenceLetterCount:
            (json['referenceLetterCount'] as num?)?.toDouble() ?? 5.0,
        lengthScaleStrength:
            (json['lengthScaleStrength'] as num?)?.toDouble() ?? 1.0,
        clausePause: Duration(milliseconds: (json['clausePauseMs'] as num?)?.toInt() ?? 90),
        sentencePause: Duration(milliseconds: (json['sentencePauseMs'] as num?)?.toInt() ?? 220),
        paragraphPause: Duration(milliseconds: (json['paragraphPauseMs'] as num?)?.toInt() ?? 400),
        minDisplay: Duration(milliseconds: (json['minDisplayMs'] as num?)?.toInt() ?? 40),
        maxDisplay: Duration(milliseconds: (json['maxDisplayMs'] as num?)?.toInt() ?? 1200),
      );
}