import 'dart:math';

import '../json_coerce.dart';
import '../pacing/pacing_config.dart';

/// How tokens are laid out on screen.
///
/// Orthogonal to [PacingModelKind]: pacing decides *when* to advance,
/// presentation decides *what is visible* — with one documented exception,
/// [continuousScroll], which supplies its own advance. [shiftingWindow] is
/// not implemented.
enum PresentationMode {
  /// One token at a time, held at a fixed anchor point.
  fixedSingle,

  /// A short window of tokens, shifting one position per advance.
  /// Not implemented.
  shiftingWindow,

  /// A single unbroken line of text drifting right to left at constant
  /// velocity, past a marked, fixed eye point.
  ///
  /// Incompatible with per-token pacing, and resolves it by outranking it:
  /// `PlaybackSession` branches on this before consulting its [PacingModel],
  /// so `Hold.pauseAfter` is not honoured as time and `AwaitAdvance` is
  /// unreachable. Speed comes from [PacingConfig.baseWpm] alone. See
  /// ADR 0025, and ADR 0003's Consequences, which predicted this.
  ///
  /// Offered because the evidence declines to rank the two formats for this
  /// project's target reader — Fine & Peli (1995) found the visually impaired
  /// reading 13% slower from RSVP than from a scroll display, and Akthar et
  /// al. (2021) found scrolling ahead of RSVP on comprehension in central
  /// vision loss. No preset selects it; see `docs/research/rsvp-evidence.md`.
  ///
  /// [PresentationConfig.orpHighlight] and [PresentationConfig.transitionMs]
  /// have no effect here. Their stored values are kept, not cleared, so
  /// switching back restores them.
  continuousScroll,
}

/// Which way round the reading surface runs.
///
/// Two values, and this package keeps it that way. A profile that states no
/// preference carries null in [PresentationConfig.polarity] rather than a
/// third value here; see that field for why.
enum Polarity { darkOnLight, lightOnDark }

/// Where the eye-point caret sits relative to the line of text, under
/// [PresentationMode.continuousScroll].
///
/// Never on the text. A marker drawn through the words obscures the one word
/// the reader is trying to read, which is the opposite of what an eye point
/// is for.
enum CaretPlacement {
  /// One caret above the line, pointing down at it.
  above,

  /// One caret below the line, pointing up at it.
  below,

  /// One of each. Most findable, and the default.
  both,
}

/// How the eye-point caret is drawn.
///
/// All three point *at* the line, so a caret above the text is the mirror of
/// the same caret below it rather than a different shape.
enum CaretStyle {
  /// A solid triangle.
  filled,

  /// The same triangle, stroked rather than filled. Quieter against a busy
  /// or heavily tinted surface.
  outline,

  /// Two strokes meeting at the tip — a chevron, with no base.
  chevron,
}

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

  /// Ink and default background, or null for the caller to decide.
  ///
  /// Null says this profile states no preference, so whoever draws supplies
  /// one through [resolvedWith]. This package holds no notion of a platform
  /// theme and cannot pick for itself. The app passes the brightness it is
  /// already running in.
  ///
  /// Null rather than a third value on [Polarity]. A `Polarity.followCaller`
  /// would reach every switch in this package on a value none of them can
  /// paint, so each one would throw or pick a side the reader never chose,
  /// and it would move every profile already on disk onto an enum value none
  /// of them were written with.
  ///
  /// Absent from [copyWith] for the same reason [tintArgb] is. Set it with
  /// [withPolarity].
  final Polarity? polarity;

  /// Background tint as ARGB, or null for the polarity default. Stored as an
  /// int so this package stays free of Flutter.
  ///
  /// Absent from [copyWith]. Set it with [withTint].
  final int? tintArgb;

  /// Highlight one letter as a fixation target. Preference only: this has
  /// no support in the studies behind the pacing models.
  final bool orpHighlight;

  /// Crossfade between tokens. 0 is an instant swap.
  final int transitionMs;

  /// Where the eye-point caret sits. Scroll mode only.
  final CaretPlacement caretPlacement;

  /// How the eye-point caret is drawn. Scroll mode only.
  final CaretStyle caretStyle;

  /// Blank between the line of text and the caret's tip, in em of
  /// [fontSizePt]. Scroll mode only.
  ///
  /// A setting rather than a constant because how far a marker has to sit
  /// from the words to stop competing with them depends on the reader's
  /// field loss, not on the type size — the same argument [anchorX] already
  /// makes for putting the eye point off centre.
  final double caretGapEm;

  /// Stroke width of an outlined or chevron caret, in em of [fontSizePt].
  /// Scroll mode only.
  ///
  /// Inert for [CaretStyle.filled], which has no stroke. The editor hides
  /// the control there rather than showing one that does nothing.
  final double caretThicknessEm;

  /// Multiplier on the caret's drawn width and depth. Scroll mode only.
  ///
  /// Separate from [caretThicknessEm] because they answer different
  /// questions — how big the marker is, and how heavy its line is — and one
  /// number driving both would be two meanings for one setting.
  final double caretScale;

  const PresentationConfig({
    this.mode = PresentationMode.fixedSingle,
    this.anchorX = 0.5,
    this.anchorY = 0.5,
    this.fontFamily,
    this.fontSizePt = 44,
    this.letterSpacingEm = 0.0,
    this.chunkSize = 1,
    this.polarity,
    this.tintArgb,
    this.orpHighlight = false,
    this.transitionMs = 0,
    this.caretPlacement = CaretPlacement.both,
    this.caretStyle = CaretStyle.filled,
    this.caretGapEm = 0.15,
    this.caretThicknessEm = 0.09,
    this.caretScale = 1,
  }) : assert(anchorX >= 0 && anchorX <= 1),
       assert(anchorY >= 0 && anchorY <= 1),
       assert(fontSizePt > 0),
       assert(
         chunkSize == 1,
         'chunkSize > 1 needs group-aware pacing, which is not built',
       ),
       assert(transitionMs >= 0),
       assert(caretGapEm >= 0 && caretGapEm <= 1),
       assert(
         caretThicknessEm >= minCaretThicknessEm &&
             caretThicknessEm <= maxCaretThicknessEm,
       ),
       assert(caretScale >= minCaretScale && caretScale <= maxCaretScale);

  /// Bounds on the two caret sizes, named once.
  ///
  /// The editor's sliders, the asserts above and the wire clamping in
  /// [PresentationConfig.fromJson] are three places that must agree about
  /// what a usable caret is; written out three times they would eventually
  /// not. A thickness of zero draws nothing and a caret larger than a line
  /// of text stops being a marker.
  static const double minCaretThicknessEm = 0.02;
  static const double maxCaretThicknessEm = 0.3;
  static const double minCaretScale = 0.5;
  static const double maxCaretScale = 2.5;

  /// Every field except the two nullable ones.
  ///
  /// [polarity] and [tintArgb] each mean something by being null, and
  /// `field ?? this.field` reads a null argument as "leave this alone", so
  /// nothing routed through here could ever put one back to unset. Both have
  /// a setter of their own instead, which leaves one way to write each.
  PresentationConfig copyWith({
    PresentationMode? mode,
    double? anchorX,
    double? anchorY,
    String? fontFamily,
    double? fontSizePt,
    double? letterSpacingEm,
    int? chunkSize,
    bool? orpHighlight,
    int? transitionMs,
    CaretPlacement? caretPlacement,
    CaretStyle? caretStyle,
    double? caretGapEm,
    double? caretThicknessEm,
    double? caretScale,
  }) => PresentationConfig(
    mode: mode ?? this.mode,
    anchorX: anchorX ?? this.anchorX,
    anchorY: anchorY ?? this.anchorY,
    fontFamily: fontFamily ?? this.fontFamily,
    fontSizePt: fontSizePt ?? this.fontSizePt,
    letterSpacingEm: letterSpacingEm ?? this.letterSpacingEm,
    chunkSize: chunkSize ?? this.chunkSize,
    polarity: polarity,
    tintArgb: tintArgb,
    orpHighlight: orpHighlight ?? this.orpHighlight,
    transitionMs: transitionMs ?? this.transitionMs,
    caretPlacement: caretPlacement ?? this.caretPlacement,
    caretStyle: caretStyle ?? this.caretStyle,
    caretGapEm: caretGapEm ?? this.caretGapEm,
    caretThicknessEm: caretThicknessEm ?? this.caretThicknessEm,
    caretScale: caretScale ?? this.caretScale,
  );

  /// Sets [polarity], null included.
  PresentationConfig withPolarity(Polarity? polarity) => PresentationConfig(
    mode: mode,
    anchorX: anchorX,
    anchorY: anchorY,
    fontFamily: fontFamily,
    fontSizePt: fontSizePt,
    letterSpacingEm: letterSpacingEm,
    chunkSize: chunkSize,
    polarity: polarity,
    tintArgb: tintArgb,
    orpHighlight: orpHighlight,
    transitionMs: transitionMs,
    caretPlacement: caretPlacement,
    caretStyle: caretStyle,
    caretGapEm: caretGapEm,
    caretThicknessEm: caretThicknessEm,
    caretScale: caretScale,
  );

  /// Sets [tintArgb], null included.
  PresentationConfig withTint(int? tintArgb) => PresentationConfig(
    mode: mode,
    anchorX: anchorX,
    anchorY: anchorY,
    fontFamily: fontFamily,
    fontSizePt: fontSizePt,
    letterSpacingEm: letterSpacingEm,
    chunkSize: chunkSize,
    polarity: polarity,
    tintArgb: tintArgb,
    orpHighlight: orpHighlight,
    transitionMs: transitionMs,
    caretPlacement: caretPlacement,
    caretStyle: caretStyle,
    caretGapEm: caretGapEm,
    caretThicknessEm: caretThicknessEm,
    caretScale: caretScale,
  );

  /// This config with [fallback] standing in for an unset [polarity].
  ///
  /// Call it above whatever paints and pass the result down. A reading
  /// surface that resolved this for itself would leave a settings preview
  /// and a contrast readout measuring the unresolved value while the reader
  /// looks at the resolved one, which is the disagreement between a preview
  /// and the real surface that this project has already had once.
  ///
  /// Leaves a profile that states a polarity alone, so the low-vision
  /// presets keep the surface their citations argue for.
  PresentationConfig resolvedWith(Polarity fallback) =>
      polarity == null ? withPolarity(fallback) : this;

  /// Writes the fields that carry a value.
  ///
  /// An unset [polarity] leaves the key out rather than writing null, which
  /// matches [fontFamily] and [tintArgb]. A client older than this field
  /// reads the absence as its own default and pins the profile, and whole
  /// profile merges under ADR 0008 mean it writes that pin back. See ADR
  /// 0016 on why the app accepts that rather than encoding around it.
  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'anchorX': anchorX,
    'anchorY': anchorY,
    if (fontFamily != null) 'fontFamily': fontFamily,
    'fontSizePt': fontSizePt,
    'letterSpacingEm': letterSpacingEm,
    'chunkSize': chunkSize,
    if (polarity != null) 'polarity': polarity!.name,
    if (tintArgb != null) 'tintArgb': tintArgb,
    'orpHighlight': orpHighlight,
    'transitionMs': transitionMs,
    'caretPlacement': caretPlacement.name,
    'caretStyle': caretStyle.name,
    'caretGapEm': caretGapEm,
    'caretThicknessEm': caretThicknessEm,
    'caretScale': caretScale,
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
      // Read through the name map rather than `enumByName`, because there is
      // no fallback to give it: a missing key is a profile that states no
      // polarity, which is the value null already carries. A name this build
      // does not know lands in the same place. It came from a build that
      // added a third value, and that name says nothing about which of these
      // two the reader would have picked, so the caller's own theme answers
      // better than a constant here does.
      polarity: Polarity.values.asNameMap()[json['polarity']],
      tintArgb: json['tintArgb'] is num ? coerceInt(json['tintArgb'], 0) : null,
      orpHighlight: coerceBool(json['orpHighlight'], fallback.orpHighlight),
      transitionMs: coerceInt(
        json['transitionMs'],
        fallback.transitionMs,
        min: 0,
      ),
      caretPlacement: enumByName(
        CaretPlacement.values,
        json['caretPlacement'],
        fallback.caretPlacement,
      ),
      caretStyle: enumByName(
        CaretStyle.values,
        json['caretStyle'],
        fallback.caretStyle,
      ),
      caretGapEm: coerceDouble(
        json['caretGapEm'],
        fallback.caretGapEm,
        min: 0,
        max: 1,
      ),
      caretThicknessEm: coerceDouble(
        json['caretThicknessEm'],
        fallback.caretThicknessEm,
        min: minCaretThicknessEm,
        max: maxCaretThicknessEm,
      ),
      caretScale: coerceDouble(
        json['caretScale'],
        fallback.caretScale,
        min: minCaretScale,
        max: maxCaretScale,
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

  /// An id for a newly forked profile.
  ///
  /// Lives here rather than in the app because the rule it has to satisfy
  /// lives here: [builtInIdPrefix] defines the namespace an id must stay out
  /// of, so the two belong together. Arithmetic whose correctness depends on
  /// the compilation target is core logic, and core logic sits in this
  /// package, where the suite runs against dart2js as well as the VM.
  ///
  /// The id travels with the sync event log, so two devices forking the same
  /// preset while offline from each other must not produce the same one. A
  /// millisecond plus 32 random bits is enough: a collision needs both the
  /// same millisecond and the same draw.
  ///
  /// Never lands in [builtInIdPrefix], so a fork cannot shadow a preset.
  static String newId() {
    final random = Random.secure();

    // Two 16-bit draws combined by multiplication, rather than one
    // nextInt(1 << 32). A shift is a 32-bit operation under dart2js, so
    // `1 << 32` is 0 there and nextInt rejects a max of zero — the same trap
    // that broke the block-id hash on web. Multiplication stays exact: the
    // result is below 2^32, well inside what a JS double represents exactly.
    final entropy = random.nextInt(0x10000) * 0x10000 + random.nextInt(0x10000);

    return 'p.${DateTime.now().toUtc().millisecondsSinceEpoch}'
        '.${entropy.toRadixString(16).padLeft(8, '0')}';
  }

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
  ///
  /// Copies the preset's presentation whole, unset polarity included. A
  /// reader forking `Standard` keeps a profile that follows the app, and a
  /// reader forking `Central field loss` keeps the light on dark that
  /// preset's citations argue for.
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
