import '../pacing/pacing_config.dart';
import 'profile.dart';

/// Built-in starting points. Every value stays adjustable afterward; a preset
/// is a place to start, not a mode.
///
/// Where a setting follows from a study, the citation is named. Where it is
/// a preference with no evidence behind it, that is said outright.
///
/// Two of these state a polarity and two leave it unset. A preset that names
/// one does so on a citation, and the app's own theme does not reach it. A
/// preset that leaves it unset takes the brightness the reader already has
/// the app in, through [PresentationConfig.resolvedWith]. See ADR 0016.
///
/// Every id here sits in [ReadingProfile.builtInIdPrefix], which is what
/// makes `isBuiltIn` true and what stops a stored or synced profile from
/// shadowing one. `presets_test.dart` checks that.
abstract final class Presets {
  /// Constant rate, centred, default type size.
  ///
  /// Aquilante et al. 2001 found normally sighted older readers fastest at a
  /// constant rate, so this is the default rather than a fallback.
  ///
  /// Polarity is unset. Nothing in the evidence picks a side for a reader
  /// with ordinary sight, and this is the profile someone opens their first
  /// book on, so it follows the app rather than dropping a white page in
  /// front of a reader who set the app dark.
  static const standard = ReadingProfile(
    id: 'builtin.standard',
    name: 'Standard',
    pacing: PacingConfig(baseWpm: 250),
  );

  /// Reader presses to advance each word.
  ///
  /// Arditi 1999: reader-elicited advance averaged 47% faster than fixed-rate
  /// RSVP in 15 slow low-vision readers, with slower readers gaining most and
  /// no predicted benefit above 133 wpm. Large type and reverse polarity are
  /// conventional low-vision defaults, not findings from that study.
  ///
  /// The polarity is written rather than left unset, so a reader who picks
  /// this preset gets light on dark whatever theme the app is in. Reversing
  /// it is most of the reason to pick it.
  static const centralFieldLoss = ReadingProfile(
    id: 'builtin.cfl.elicited',
    name: 'Central field loss',
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
  ///
  /// Polarity written, for the reason on [centralFieldLoss].
  static const centralFieldLossTimed = ReadingProfile(
    id: 'builtin.cfl.timed',
    name: 'Central field loss (timed)',
    pacing: PacingConfig(kind: PacingModelKind.lengthScaled, baseWpm: 120),
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
  ///
  /// Polarity is unset. What this preset changes is spacing and rate, and
  /// neither study behind it looked at contrast polarity, so it has nothing
  /// to say about which way round the surface runs.
  static const spacedType = ReadingProfile(
    id: 'builtin.spaced',
    name: 'Spaced type',
    pacing: PacingConfig(
      baseWpm: 180,
      clausePause: Duration(milliseconds: 140),
      sentencePause: Duration(milliseconds: 320),
    ),
    presentation: PresentationConfig(fontSizePt: 40, letterSpacingEm: 0.12),
  );

  /// Low rate, gentle contrast, crossfade between words.
  ///
  /// Preference, not evidence. Intended for long sessions where the goal is
  /// to keep going rather than to finish quickly.
  ///
  /// The polarity is written even though no study picks it, because a reader
  /// choosing this one is choosing the dark surface along with the slow rate
  /// and the fade. Leaving it unset would hand a light app a bright page
  /// under the name "Low fatigue".
  static const lowFatigue = ReadingProfile(
    id: 'builtin.lowfatigue',
    name: 'Low fatigue',
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
