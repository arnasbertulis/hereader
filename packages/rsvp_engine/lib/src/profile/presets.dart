import '../pacing/pacing_config.dart';
import 'profile.dart';

/// Built-in starting points. Every value stays adjustable afterward; a preset
/// is a place to start, not a mode.
///
/// Where a setting follows from a study, the citation is named. Where it is
/// a preference with no evidence behind it, that is said outright.
abstract final class Presets {
  /// Constant rate, centred, default type size.
  ///
  /// Aquilante et al. 2001 found normally sighted older readers fastest at a
  /// constant rate, so this is the default rather than a fallback.
  static const standard = ReadingProfile(
    id: 'builtin.standard',
    name: 'Standard',
    isBuiltIn: true,
    pacing: PacingConfig(baseWpm: 250),
  );

  /// Reader presses to advance each word.
  ///
  /// Arditi 1999: reader-elicited advance averaged 47% faster than fixed-rate
  /// RSVP in 15 slow low-vision readers, with slower readers gaining most and
  /// no predicted benefit above 133 wpm. Large type and reverse polarity are
  /// conventional low-vision defaults, not findings from that study.
  static const centralFieldLoss = ReadingProfile(
    id: 'builtin.cfl.elicited',
    name: 'Central field loss',
    isBuiltIn: true,
    pacing: PacingConfig(kind: PacingModelKind.elicited),
    presentation: PresentationConfig(
      fontSizePt: 48,
      polarity: Polarity.lightOnDark,
    ),
  );

  /// Timed alternative for readers who prefer a stream to pressing a button.
  ///
  /// Aquilante et al. 2001: scaling display duration by word length carried
  /// central-field-loss readers through sentences about 33% faster than a
  /// constant rate. Starting rate is deliberately low; Arditi's ceiling
  /// suggests the elicited profile above suits readers below roughly 133 wpm
  /// better than any timed rate does.
  static const centralFieldLossTimed = ReadingProfile(
    id: 'builtin.cfl.timed',
    name: 'Central field loss (timed)',
    isBuiltIn: true,
    pacing: PacingConfig(
      kind: PacingModelKind.lengthScaled,
      baseWpm: 120,
    ),
    presentation: PresentationConfig(
      fontSizePt: 48,
      polarity: Polarity.lightOnDark,
    ),
  );

  /// Wider letter spacing, slower rate, longer punctuation pauses.
  ///
  /// Zorzi et al. 2012 reported that extra letter spacing helped dyslexic
  /// children, and Skottun and Skoyles published a critique the same year.
  /// The control is offered without an efficacy claim.
  static const spacedType = ReadingProfile(
    id: 'builtin.spaced',
    name: 'Spaced type',
    isBuiltIn: true,
    pacing: PacingConfig(
      baseWpm: 180,
      clausePause: Duration(milliseconds: 140),
      sentencePause: Duration(milliseconds: 320),
    ),
    presentation: PresentationConfig(
      fontSizePt: 40,
      letterSpacingEm: 0.12,
    ),
  );

  /// Low rate, gentle contrast, crossfade between words.
  ///
  /// Preference, not evidence. Intended for long sessions where the goal is
  /// to keep going rather than to finish quickly.
  static const lowFatigue = ReadingProfile(
    id: 'builtin.lowfatigue',
    name: 'Low fatigue',
    isBuiltIn: true,
    rewindWords: 3,
    pacing: PacingConfig(
      baseWpm: 200,
      sentencePause: Duration(milliseconds: 300),
      paragraphPause: Duration(milliseconds: 600),
    ),
    presentation: PresentationConfig(
      fontSizePt: 36,
      polarity: Polarity.lightOnDark,
      transitionMs: 60,
    ),
  );

  static const all = <ReadingProfile>[
    standard,
    centralFieldLoss,
    centralFieldLossTimed,
    spacedType,
    lowFatigue,
  ];

  static ReadingProfile? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}