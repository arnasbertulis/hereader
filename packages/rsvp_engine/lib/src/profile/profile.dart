import '../json_coerce.dart';
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
  }) : assert(anchorX >= 0 && anchorX <= 1),
       assert(anchorY >= 0 && anchorY <= 1),
       assert(fontSizePt > 0),
       assert(
         chunkSize == 1,
         'chunkSize > 1 needs group-aware pacing, which is not built',
       ),
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
  }) => PresentationConfig(
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

  /// Reads presentation settings written by any build of this package.
  ///
  /// The asserts above hold for values this app constructs and cannot hold
  /// for values arriving through sync. Out-of-range numbers move to the
  /// nearest bound rather than throwing; see `json_coerce.dart` for why a
  /// throw here would lose the reader's change permanently.
  factory PresentationConfig.fromJson(Map<String, dynamic> json) {
    const fallback = PresentationConfig();

    return PresentationConfig(
      mode: enumByName(PresentationMode.values, json['mode'], fallback.mode),
      anchorX: coerceDouble(json['anchorX'], fallback.anchorX, min: 0, max: 1),
      anchorY: coerceDouble(json['anchorY'], fallback.anchorY, min: 0, max: 1),
      fontFamily: coerceStringOrNull(json['fontFamily']),
      fontSizePt: coerceDouble(json['fontSizePt'], fallback.fontSizePt, min: 1),
      letterSpacingEm: coerceDouble(
        json['letterSpacingEm'],
        fallback.letterSpacingEm,
        min: 0,
      ),
      // Pinned to 1 rather than clamped to a range. A build that renders
      // groups will send something larger, and this one cannot draw it.
      // Reading one word per advance is not what that reader configured, but
      // it is legible; refusing the profile would lose their type size and
      // contrast along with it.
      chunkSize: coerceInt(json['chunkSize'], 1, min: 1, max: 1),
      polarity: enumByName(
        Polarity.values,
        json['polarity'],
        fallback.polarity,
      ),
      tintArgb: json['tintArgb'] is num ? coerceInt(json['tintArgb'], 0) : null,
      orpHighlight: coerceBool(json['orpHighlight'], fallback.orpHighlight),
      transitionMs: coerceInt(
        json['transitionMs'],
        fallback.transitionMs,
        min: 0,
      ),
    );
  }
}

/// A named bundle of pacing and presentation settings.
///
/// [id] is stable and travels with the sync event log. [name] is what the
/// reader sees and may be edited.
class ReadingProfile {
  /// Ids in this namespace belong to code rather than to the reader.
  ///
  /// Nothing stored or synced may claim one. A stored row shadowing a preset
  /// would show twice in the reader's list, and an inbound event could
  /// replace a preset the app guarantees is always available.
  static const builtInIdPrefix = 'builtin.';

  final String id;
  final String name;
  final PacingConfig pacing;
  final PresentationConfig presentation;

  /// Tokens to step back when resuming after a pause, so the reader
  /// re-enters mid-sentence with some context.
  final int rewindWords;

  const ReadingProfile({
    required this.id,
    required this.name,
    this.pacing = const PacingConfig(),
    this.presentation = const PresentationConfig(),
    this.rewindWords = 2,
  }) : assert(id != ''),
       assert(rewindWords >= 0);

  /// True for profiles shipped with the app. The UI copies rather than
  /// edits these.
  ///
  /// Derived from [id] rather than stored. A stored flag would be a second
  /// source of truth for one fact, and a profile arriving through sync could
  /// set it: a payload claiming to be a preset would render as a profile the
  /// reader can neither edit nor delete.
  bool get isBuiltIn => id.startsWith(builtInIdPrefix);

  ReadingProfile copyWith({
    String? id,
    String? name,
    PacingConfig? pacing,
    PresentationConfig? presentation,
    int? rewindWords,
  }) => ReadingProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    pacing: pacing ?? this.pacing,
    presentation: presentation ?? this.presentation,
    rewindWords: rewindWords ?? this.rewindWords,
  );

  /// Derive an editable copy of a built-in profile.
  ///
  /// The caller supplies the id, so the namespace is checked here: a fork
  /// keeping a preset's id would shadow that preset in the reader's list and
  /// would be refused by the repository on save.
  ReadingProfile fork({required String id, String? name}) {
    if (id.startsWith(builtInIdPrefix)) {
      throw ArgumentError.value(
        id,
        'id',
        'a fork cannot take an id in the built-in namespace',
      );
    }

    return copyWith(id: id, name: name ?? '${this.name} (copy)');
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pacing': pacing.toJson(),
    'presentation': presentation.toJson(),
    'rewindWords': rewindWords,
  };

  /// Reads a profile written by any build of this package.
  ///
  /// Every field degrades except [id], which has no sensible fallback: a
  /// profile without one cannot be stored, compared, or synced. The sync
  /// client writes the service's own entity id into the payload before
  /// calling this, so an event reaching here always carries one.
  factory ReadingProfile.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw FormatException('Profile JSON carries no id: $json');
    }

    final pacing = coerceMap(json['pacing']);
    final presentation = coerceMap(json['presentation']);

    return ReadingProfile(
      id: id,
      name: coerceString(json['name'], 'Unnamed'),
      pacing: pacing == null
          ? const PacingConfig()
          : PacingConfig.fromJson(pacing),
      presentation: presentation == null
          ? const PresentationConfig()
          : PresentationConfig.fromJson(presentation),
      rewindWords: coerceInt(json['rewindWords'], 2, min: 0),
    );
  }
}
