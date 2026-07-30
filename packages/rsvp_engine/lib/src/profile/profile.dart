import '../pacing/pacing_config.dart';

/// How tokens are laid out on screen.
///
/// Orthogonal to [PacingModelKind]: pacing decides *when* to advance,
/// presentation decides *what is visible*. Only [fixedSingle] is implemented.
enum PresentationMode {
  /// One token at a time, held at a fixed anchor point.
  fixedSingle,

  /// A short window of tokens, shifting one position per advance.
  /// Not implemented.
  shiftingWindow,

  /// Text drifting at constant velocity. Incompatible with per-token
  /// pacing; see ADR 0003. Not implemented.
  continuousScroll,
}

enum Polarity { darkOnLight, lightOnDark }

/// Everything about how text is drawn. No timing.
class PresentationConfig {
  final PresentationMode mode;

  /// Anchor position as a fraction of the reading surface, 0.0 to 1.0.
  /// Readers with a scotoma to one side often want this off centre.
  final double anchorX;
  final double anchorY;

  /// Null means the platform default. The app resolves this to a real font.
  final String? fontFamily;
  final double fontSizePt;

  /// Extra letter spacing in em units. 0.0 is the font's own spacing.
  final double letterSpacingEm;

  /// Tokens shown per advance. Only 1 is supported: values above 1 require
  /// pacing to decide over a group rather than a token, which the engine
  /// does not yet do.
  final int chunkSize;

  final Polarity polarity;

  /// Background tint as ARGB, or null for the polarity default. Stored as an
  /// int so this package stays free of Flutter.
  final int? tintArgb;

  /// Highlight one letter as a fixation target. Preference only: this has
  /// no support in the studies behind the pacing models.
  final bool orpHighlight;

  /// Crossfade between tokens. 0 is an instant swap.
  final int transitionMs;

  const PresentationConfig({
    this.mode = PresentationMode.fixedSingle,
    this.anchorX = 0.5,
    this.anchorY = 0.5,
    this.fontFamily,
    this.fontSizePt = 44,
    this.letterSpacingEm = 0.0,
    this.chunkSize = 1,
    this.polarity = Polarity.darkOnLight,
    this.tintArgb,
    this.orpHighlight = false,
    this.transitionMs = 0,
  })  : assert(anchorX >= 0 && anchorX <= 1),
        assert(anchorY >= 0 && anchorY <= 1),
        assert(fontSizePt > 0),
        assert(chunkSize == 1,
            'chunkSize > 1 needs group-aware pacing, which is not built'),
        assert(transitionMs >= 0);

  PresentationConfig copyWith({
    PresentationMode? mode,
    double? anchorX,
    double? anchorY,
    String? fontFamily,
    double? fontSizePt,
    double? letterSpacingEm,
    int? chunkSize,
    Polarity? polarity,
    int? tintArgb,
    bool? orpHighlight,
    int? transitionMs,
  }) =>
      PresentationConfig(
        mode: mode ?? this.mode,
        anchorX: anchorX ?? this.anchorX,
        anchorY: anchorY ?? this.anchorY,
        fontFamily: fontFamily ?? this.fontFamily,
        fontSizePt: fontSizePt ?? this.fontSizePt,
        letterSpacingEm: letterSpacingEm ?? this.letterSpacingEm,
        chunkSize: chunkSize ?? this.chunkSize,
        polarity: polarity ?? this.polarity,
        tintArgb: tintArgb ?? this.tintArgb,
        orpHighlight: orpHighlight ?? this.orpHighlight,
        transitionMs: transitionMs ?? this.transitionMs,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'anchorX': anchorX,
        'anchorY': anchorY,
        if (fontFamily != null) 'fontFamily': fontFamily,
        'fontSizePt': fontSizePt,
        'letterSpacingEm': letterSpacingEm,
        'chunkSize': chunkSize,
        'polarity': polarity.name,
        if (tintArgb != null) 'tintArgb': tintArgb,
        'orpHighlight': orpHighlight,
        'transitionMs': transitionMs,
      };

  factory PresentationConfig.fromJson(Map<String, dynamic> json) =>
      PresentationConfig(
        mode: _enumByName(
            PresentationMode.values, json['mode'], PresentationMode.fixedSingle),
        anchorX: (json['anchorX'] as num?)?.toDouble() ?? 0.5,
        anchorY: (json['anchorY'] as num?)?.toDouble() ?? 0.5,
        fontFamily: json['fontFamily'] as String?,
        fontSizePt: (json['fontSizePt'] as num?)?.toDouble() ?? 32,
        letterSpacingEm: (json['letterSpacingEm'] as num?)?.toDouble() ?? 0.0,
        chunkSize: (json['chunkSize'] as num?)?.toInt() ?? 1,
        polarity:
            _enumByName(Polarity.values, json['polarity'], Polarity.darkOnLight),
        tintArgb: (json['tintArgb'] as num?)?.toInt(),
        orpHighlight: json['orpHighlight'] as bool? ?? false,
        transitionMs: (json['transitionMs'] as num?)?.toInt() ?? 0,
      );
}

/// A named bundle of pacing and presentation settings.
///
/// [id] is stable and travels with the sync event log. [name] is what the
/// reader sees and may be edited.
class ReadingProfile {
  final String id;
  final String name;
  final PacingConfig pacing;
  final PresentationConfig presentation;

  /// Tokens to step back when resuming after a pause, so the reader
  /// re-enters mid-sentence with some context.
  final int rewindWords;

  /// True for profiles shipped with the app. The UI copies rather than
  /// edits these.
  final bool isBuiltIn;

  const ReadingProfile({
    required this.id,
    required this.name,
    this.pacing = const PacingConfig(),
    this.presentation = const PresentationConfig(),
    this.rewindWords = 2,
    this.isBuiltIn = false,
  })  : assert(id != ''),
        assert(rewindWords >= 0);

  ReadingProfile copyWith({
    String? id,
    String? name,
    PacingConfig? pacing,
    PresentationConfig? presentation,
    int? rewindWords,
    bool? isBuiltIn,
  }) =>
      ReadingProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        pacing: pacing ?? this.pacing,
        presentation: presentation ?? this.presentation,
        rewindWords: rewindWords ?? this.rewindWords,
        isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      );

  /// Derive an editable copy of a built-in profile.
  ReadingProfile fork({required String id, String? name}) => copyWith(
        id: id,
        name: name ?? '${this.name} (copy)',
        isBuiltIn: false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pacing': pacing.toJson(),
        'presentation': presentation.toJson(),
        'rewindWords': rewindWords,
        'isBuiltIn': isBuiltIn,
      };

  factory ReadingProfile.fromJson(Map<String, dynamic> json) => ReadingProfile(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Unnamed',
        pacing: json['pacing'] == null
            ? const PacingConfig()
            : PacingConfig.fromJson(json['pacing'] as Map<String, dynamic>),
        presentation: json['presentation'] == null
            ? const PresentationConfig()
            : PresentationConfig.fromJson(
                json['presentation'] as Map<String, dynamic>),
        rewindWords: (json['rewindWords'] as num?)?.toInt() ?? 2,
        isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      );
}

/// Resolve an enum by name, falling back rather than throwing.
///
/// A device running an older build may receive a profile from a newer one
/// through sync. Unknown values degrade to the default instead of making the
/// whole profile unreadable.
T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}