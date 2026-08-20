import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// Turning a [ReadingProfile] into things a screen can show, and the single
/// home for colour in this app.
///
/// The engine stores colours as ARGB integers so it stays free of Flutter.
/// Everything that maps those to real colours, judges whether the result is
/// legible, builds a theme from them, or writes a profile out in words
/// belongs here rather than in a widget.

// -- resolving a profile's polarity ---------------------------------------

/// A [PresentationConfig] whose polarity someone has decided.
///
/// A profile may leave [PresentationConfig.polarity] null, which says the
/// reader wants whatever the app is set to. Nothing below can paint that: a
/// surface colour, a chrome brightness and a contrast figure all need a side.
/// So the type says which configs are ready, and [resolvePresentation] is the
/// only way to make one.
///
/// A screen resolves once, near the top of its build, and passes the result
/// down. That is a rule the compiler now holds rather than a comment: the
/// reading surface, the settings preview and the contrast readout all take
/// this type, so none of them can measure or draw a polarity that another one
/// resolved differently. Two of them disagreeing is what put a WCAG figure in
/// settings against a colour pair the app never drew, and that arrangement
/// looked correct in both files at the time.
///
/// An extension type rather than a class: it compiles away to the config
/// itself, so a wrapper on the widget that rebuilds per word costs nothing.
/// Rejected a plain wrapper class for that reason, and rejected an assert
/// inside [surfaceArgbFor] because an assert fires in a debug run of a screen
/// somebody opened, while this fires in `flutter analyze` on every screen at
/// once.
extension type ResolvedPresentation._(PresentationConfig config) {
  /// The decided polarity.
  ///
  /// Never null. [resolvePresentation] is the only constructor and it runs
  /// [PresentationConfig.resolvedWith], which fills this field or leaves a
  /// value already there alone.
  Polarity get polarity => config.polarity!;
}

/// The polarity a profile takes when it states none.
///
/// Dark app, dark page. The reader who set the app dark and then opened a
/// book into a white surface is the whole reason ADR 0016 exists.
///
/// [appBrightness] is the brightness the app is running in, which is
/// `Theme.of(context).brightness` read above any theme the reader screen puts
/// over it. Theme mode is device-local under ADR 0012, so a profile that
/// states no polarity draws light on a phone set light and dark on a desktop
/// set dark, both signed into the same account. That follows from theme mode
/// being device-local rather than working around it.
Polarity _polarityFor(Brightness appBrightness) => switch (appBrightness) {
  Brightness.light => Polarity.darkOnLight,
  Brightness.dark => Polarity.lightOnDark,
};

/// Decides [presentation]'s polarity, where the profile left it open.
///
/// Leaves a profile that names a polarity alone, which is what keeps
/// `Central field loss` reversed inside a light app. Those presets cite
/// Aquilante and Arditi for that surface; the app's theme is not evidence and
/// does not get to overrule it.
ResolvedPresentation resolvePresentation(
  PresentationConfig presentation,
  Brightness appBrightness,
) => ResolvedPresentation._(
  presentation.resolvedWith(_polarityFor(appBrightness)),
);

// -- polarity defaults --------------------------------------------------

/// The colours a profile falls back to when it carries no tint.
///
/// Not pure black on pure white: maximum contrast is uncomfortable over a
/// long session for many readers, and the difference in ratio is negligible.
///
/// These are the only definition. `rsvp_view.dart` reads them through
/// [inkArgbFor] and [surfaceArgbFor] rather than carrying its own copies,
/// which it did until this file's own comment turned out to be describing an
/// arrangement that had already come apart: the surface painted 0xFF080808
/// against a readout measuring 0xFF101010, so the WCAG figure in settings
/// judged a colour pair the app never drew.
const int lightSurfaceArgb = 0xFFFAFAFA;
const int darkInkArgb = 0xFF121212;
const int darkSurfaceArgb = 0xFF101010;
const int lightInkArgb = 0xFFF5F5F5;

/// The fixation letter, when a profile asks for one.
///
/// One colour for both polarities. It is a marker rather than text, and its
/// job is to be findable at a glance rather than to be read, so it does not
/// follow the ink. Not included in the contrast readout for the same reason:
/// see the note in `_ContrastReadout`.
const int orpArgb = 0xFFD23B2E;

/// The text colour implied by a polarity.
///
/// Text colour is not a separate setting. The engine carries a tint for the
/// background only, so polarity is what decides the ink.
int inkArgbFor(Polarity polarity) => switch (polarity) {
  Polarity.darkOnLight => darkInkArgb,
  Polarity.lightOnDark => lightInkArgb,
};

/// The background colour a profile will actually be drawn on.
///
/// Takes a resolved config, because a profile following the app has no
/// polarity of its own to switch on here.
int surfaceArgbFor(ResolvedPresentation presentation) =>
    presentation.config.tintArgb ??
    switch (presentation.polarity) {
      Polarity.darkOnLight => lightSurfaceArgb,
      Polarity.lightOnDark => darkSurfaceArgb,
    };

// -- ARGB formatting ------------------------------------------------------
//
// The component accessors (`alphaOf`, `redOf`, `greenOf`, `blueOf`,
// `argbFrom`) and the WCAG contrast maths (`relativeLuminance`,
// `contrastRatio`, `ContrastRating`, `rateContrast`) moved to
// `package:rsvp_engine` in the UI pass: none of them touch Flutter, and
// keeping them here put them on the one platform the CI browser run cannot
// reach. See `contrast.dart` in rsvp_engine for the maths and its own
// history comment.

Color colorOf(int argb) =>
    Color.fromARGB(alphaOf(argb), redOf(argb), greenOf(argb), blueOf(argb));

/// Six-digit hex, for a reader who wants to write a value down or match one.
String hexOf(int argb) =>
    '#${(redOf(argb) * 0x10000 + greenOf(argb) * 0x100 + blueOf(argb)).toRadixString(16).padLeft(6, '0').toUpperCase()}';

// -- contrast wording -------------------------------------------------------

String contrastLabel(ContrastRating rating) => switch (rating) {
  ContrastRating.high => 'High contrast',
  ContrastRating.adequate => 'Adequate contrast',
  ContrastRating.low => 'Low contrast',
  ContrastRating.veryLow => 'Very low contrast',
};

String contrastAdvice(ContrastRating rating) => switch (rating) {
  ContrastRating.high => 'Comfortable for most readers.',
  ContrastRating.adequate => 'Readable, though less so in bright light.',
  ContrastRating.low => 'Hard to read for many people with low vision.',
  ContrastRating.veryLow => 'The text may be effectively invisible.',
};

// -- chrome -------------------------------------------------------------
//
// `hereaderSeed` and `appTheme` moved to `app_theme.dart` in the UI pass.
// What stayed here is everything that has to read the profile to decide a
// colour, which is what the reading surface's own chrome does.
//
// This section used to seed a whole `ColorScheme` from a fixed colour and
// hand it to every control on the reading surface. That colour was
// `0xFF6750A4`, Material's own baseline, so the four tonal buttons, the
// progress bar and the panel all came out purple under every profile. ADR
// 0015 replaced the arrangement rather than the constant: `fromSeed`'s
// default `tonalSpot` variant tints surfaces with whatever it is given, so
// a grey seed would have moved the wash rather than removed it.

/// The bar a control on the reading surface has to clear.
///
/// WCAG 1.4.11, which asks 3:1 for anything needed to identify a control.
/// Not 4.5:1: nothing on the reading surface is text after ADR 0015, and the
/// worst background a reader can reach sits near the 0.179 luminance flip,
/// where no overlay clears 4.5 in either direction.
const double readerMinControlContrast = 3;

/// How much of the ink the progress track keeps.
///
/// The track is the unfilled remainder of a bar whose fill carries the
/// figure, so it wants to be visible without competing with the fill.
///
/// 0.16 rather than the 0.24 this shipped with. The figure is set by the
/// fill's fallback rather than by appearance: on a background near the 0.179
/// flip, the ink against a track at 0.24 reaches 2.93, so
/// [readerProgressFillFor] would have swapped a fill that failed
/// [readerMinControlContrast] for one that also failed it. At 0.16 the worst
/// of the same set is 3.31, and the track still separates from the surface
/// by 1.26 to 1.55, which is a groove rather than a second bar.
const double _readerTrackOpacity = 0.16;

/// Whether controls drawn on this profile's reading surface should be light
/// or dark.
///
/// Read from the surface's own luminance rather than from [Polarity].
/// Polarity decides the ink, and a reader is free to tint the background
/// until the two barely differ — [rateContrast] says so and deliberately
/// does not block it. Chrome is a different question. It sits on the
/// surface, it is not configurable, and its only job is to stay legible
/// against whatever is behind it, so a dark tint under `darkOnLight` gets
/// dark chrome even though the ink stays dark too.
///
/// 0.179 is where a colour's contrast against black equals its contrast
/// against white under the WCAG formula, which is exactly the point at
/// which the better choice of overlay flips.
Brightness chromeBrightnessFor(ResolvedPresentation presentation) =>
    relativeLuminance(surfaceArgbFor(presentation)) > 0.179
    ? Brightness.light
    : Brightness.dark;

/// The colour of a glyph drawn straight onto the reading surface.
///
/// The playback controls and the chapter button carried a filled tonal disc
/// until ADR 0015, which gave each glyph a known background to contrast
/// against. Without the disc they sit on whatever the reader chose in the
/// background picker, which accepts arbitrary RGB, so the colour has to
/// follow the surface rather than a theme role.
///
/// Reuses the reading ink values rather than defining a second pair. A
/// reader who has tinted nothing then sees one monochrome surface, and a
/// reader who has tinted heavily sees chrome that agrees with
/// [chromeBrightnessFor] even where that disagrees with [Polarity].
///
/// The floor is a tint sitting on the 0.179 threshold, where the better of
/// the two clears about 4.1:1. WCAG 1.4.11 asks 3:1 for a control that is
/// not text, which every glyph here is; `reader_chrome_test.dart` measures
/// the whole preset list and both polarity defaults against that bar.
int readerInkArgbFor(ResolvedPresentation presentation) =>
    chromeBrightnessFor(presentation) == Brightness.light
    ? darkInkArgb
    : lightInkArgb;

/// The unfilled part of the progress bar.
///
/// Returned already blended against the surface rather than as the ink at an
/// alpha. The widget paints this exact colour and `reader_chrome_test.dart`
/// measures this exact colour, so neither can be right about a pair the
/// other never had. Handing `LinearProgressIndicator` a translucent
/// background and re-deriving the composite in a test is the arrangement
/// that had the WCAG readout in settings judging a pair the app never drew.
Color readerTrackFor(ResolvedPresentation presentation) => Color.alphaBlend(
  colorOf(
    readerInkArgbFor(presentation),
  ).withValues(alpha: _readerTrackOpacity),
  colorOf(surfaceArgbFor(presentation)),
);

/// The accent where it reads against [background], the ink where it does not.
///
/// Two things on the reading surface take the accent and they sit on
/// different backgrounds — the progress fill on its own track, the scroll
/// caret on the bare surface — so the background is a parameter rather than
/// baked in. One function, because a second one measuring a different pair
/// is how the contrast readout came to report colours the app never painted.
///
/// Falls back to the ink rather than to a lightened accent: a washed accent
/// is still an accent and would report a colour the reader did not choose.
Color readerAccentOn(
  Color background, {
  required ColorScheme scheme,
  required ResolvedPresentation presentation,
}) {
  final reads =
      contrastRatio(scheme.primary.toARGB32(), background.toARGB32()) >=
      readerMinControlContrast;

  return reads ? scheme.primary : colorOf(readerInkArgbFor(presentation));
}

/// The filled part of the progress bar: the accent where it reads, the ink
/// where it does not.
///
/// The fill is the one accent on the reading surface, and the reader picks
/// both the accent and the background, on two different screens that know
/// nothing about each other. ADR 0015 first recorded the overlap as a
/// limitation and left `scheme.primary` in place unguarded. The test that
/// measures six accents against every reachable background failed at 1.92,
/// on a tint near the 0.179 flip where the track sits mid-luminance and
/// nothing contrasts well with it.
///
/// The guard was rejected once on the grounds that it would change the bar's
/// colour while the reader dragged the background picker. That was wrong
/// about the screen: `_Preview` in `profile_edit_screen.dart` draws
/// `RsvpView` and the contrast readout, and no controls, so the bar is not
/// visible during the drag.
///
/// Falling back to the ink rather than to a lightened accent, because a
/// washed accent is still an accent and would report a colour the reader did
/// not choose. Monochrome is what the rest of this screen already is.
///
/// ADR 0016 widens the set of backgrounds this has to survive: a profile
/// following the app reaches both polarity defaults on one device, depending
/// on the theme the reader has it in, so the fallback can now fire on a book
/// that did not fire it yesterday.
Color readerProgressFillFor({
  required ColorScheme scheme,
  required ResolvedPresentation presentation,
}) => readerAccentOn(
  readerTrackFor(presentation),
  scheme: scheme,
  presentation: presentation,
);

/// The eye-point caret on the sliding surface: the accent where it reads
/// against the reading surface itself, the ink where it does not.
///
/// The caret is measured against `surfaceArgbFor` rather than against the
/// progress track, because that is what is actually behind it. Routing it
/// through [readerProgressFillFor] would have judged a pair it never sits
/// on — the exact shape of the bug `RsvpView`'s doc comment records.
///
/// This is the second accented object on the reading surface, which widens
/// ADR 0015's one-accent-per-screen rule. Deliberate: the caret is the eye
/// point, which is the single thing a reader of a moving line has to find,
/// and it is only ever on screen beside the progress fill while the text is
/// stopped. See ADR 0025.
Color readerCaretFor({
  required ColorScheme scheme,
  required ResolvedPresentation presentation,
}) => readerAccentOn(
  colorOf(surfaceArgbFor(presentation)),
  scheme: scheme,
  presentation: presentation,
);

/// A theme for the panels the reader screen opens over its surface.
///
/// The chapter drawer, the profile sheet and the front matter offer are
/// panels: they have their own background, so they take the app's neutral
/// ramp through [buildScheme] and read like the rest of the app. The
/// controls drawn directly on the reading surface do not use this scheme's
/// surface roles at all, and take [readerInkArgbFor] instead.
///
/// [brightness] comes from the profile rather than the platform, so a book
/// read light on dark keeps a dark panel over it even on a device set to
/// light. Under ADR 0016 a profile that states no polarity has already taken
/// the platform's brightness by the time it arrives here, so the two agree by
/// construction rather than by coincidence. [accent] and [highContrast]
/// arrive from `AppChromeSource`, which carries the reader's own appearance
/// choices down from `appTheme`.
///
/// The accent reaches exactly one thing here, `scheme.primary` on the
/// progress fill and the selected chapter row. This file used to argue that
/// no accent should reach the reading surface, on the grounds that a moss
/// background under a rust accent puts two chosen colours side by side. ADR
/// 0015 takes the narrower position: that argument holds against four tonal
/// fills and a full-width bar, and it does not hold against a single
/// measurement, which is the one thing on the screen that has a quantity to
/// report.
///
/// `scaffoldBackgroundColor` matches the profile so nothing shows through at
/// the edges during a route transition.
ThemeData readerChromeTheme({
  required ResolvedPresentation presentation,
  required Color accent,
  required bool highContrast,
}) {
  final brightness = chromeBrightnessFor(presentation);
  final scheme = buildScheme(
    accent: accent,
    brightness: brightness,
    highContrast: highContrast,
  );
  final hairlineWidth = highContrast
      ? AppHairline.widthHighContrast
      : AppHairline.width;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: appTextTheme(scheme),
    scaffoldBackgroundColor: colorOf(surfaceArgbFor(presentation)),

    // The panels were taking Material's defaults for type and separation
    // while every other screen took the app's, so a chapter list opened
    // over a book in a different face and a different line weight from the
    // library list it was opened from.
    drawerTheme: DrawerThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.md)),
      ),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      selectedColor: scheme.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
    ),

    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: hairlineWidth,
      space: hairlineWidth,
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        minimumSize: const Size(48, 48),
        textStyle: appTextTheme(scheme).labelLarge,
      ),
    ),
  );
}

/// The type the reading surface draws in.
///
/// One function, because both surfaces need it and continuous scroll needs
/// it *twice* — once to measure the run and once to paint it. Three copies
/// of one style is three chances for the geometry the session walks to stop
/// matching the glyphs on screen.
TextStyle readingTextStyle(ResolvedPresentation presentation) {
  final config = presentation.config;

  return TextStyle(
    fontFamily: config.fontFamily,
    fontSize: config.fontSizePt,
    letterSpacing: config.fontSizePt * config.letterSpacingEm,
    height: 1.2,
    color: colorOf(inkArgbFor(presentation.polarity)),
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

// -- descriptions -------------------------------------------------------

/// The pacing to *estimate* a time from, for a profile.
///
/// Continuous scroll always has a rate, including under elicited pacing:
/// the marquee outranks the pacing model, so nothing waits for the reader
/// and `baseWpm` describes the text going past. Seconds per token there is
/// `meanAdvance / velocity`, and velocity is `(baseWpm / 60) * meanAdvance`,
/// so the mean width divides out and the answer is exactly what
/// [remainingReadingTime] already computes for constant pacing.
///
/// A substitution at the call site rather than a second estimator. One
/// function still computes this figure, and `PacingModel` still knows
/// nothing about presentation — ADR 0003 §3 holds. The substitution is
/// honest: under scroll the pacing genuinely is constant.
///
/// ADR 0014's rule is unchanged for the fixed anchor. The estimate is
/// withheld when there is no rate; scroll always has one.
PacingConfig estimationPacing(ReadingProfile profile) =>
    profile.presentation.mode == PresentationMode.continuousScroll
    ? profile.pacing.copyWith(kind: PacingModelKind.constant)
    : profile.pacing;

/// Says when the crossfade outlasts the word it is fading.
///
/// `AnimatedSwitcher` begins a new transition each time the word changes, so
/// a fade longer than a word's time on screen leaves the outgoing word still
/// visible when the next arrives. At a fixed anchor that is two words drawn
/// on top of each other, which is the one thing single-word presentation
/// exists to avoid.
///
/// Nothing acts on this. Warned about rather than clamped, as the contrast
/// readout is: the value is not unsafe and a reader may want it, but nobody
/// should arrive at overlapping words without being told.
String? fadeWarning(ReadingProfile profile) {
  // Continuous scroll fades nothing: there is no moment at which one word
  // replaces another, so `transitionMs` has no effect and a warning about it
  // would be describing a control that is not on screen.
  if (profile.presentation.mode == PresentationMode.continuousScroll) {
    return null;
  }

  final display = referenceDisplay(profile.pacing);
  if (display == null) return null;

  final fade = profile.presentation.transitionMs;
  if (fade <= display.inMilliseconds) return null;

  return 'Longer than the ${display.inMilliseconds} ms each word is shown, '
      'so words will overlap as one fades into the next.';
}

/// Says that a continuously moving surface is about to ignore a system
/// preference asking for less motion.
///
/// Warned about rather than acted on, like [fadeWarning] and the contrast
/// readout. Reduce-motion exists to suppress decoration that moves; here the
/// motion *is* the reading method, and a reader who chose this mode chose it
/// knowing what their device asks for generally. Silently falling back to a
/// fixed anchor would take away the thing they selected. Nobody should
/// arrive at it uninformed, which is what this line is for.
String? reduceMotionWarning(ReadingProfile profile, {required bool disabled}) {
  if (!disabled) return null;
  if (profile.presentation.mode != PresentationMode.continuousScroll) {
    return null;
  }

  return 'Your device asks apps to reduce motion. This mode moves text '
      'continuously and will keep doing so.';
}

/// How a presentation mode reads, in the reader's terms.
///
/// [PresentationMode.shiftingWindow] is not built and never reaches a
/// reader-facing control, so it is not described. The switch is exhaustive
/// rather than defaulted, so building it would be a compile error here.
String describePresentationMode(PresentationMode mode) => switch (mode) {
  PresentationMode.fixedSingle =>
    'One word at a time, held where your eyes already are. Cuts about 1.3 '
        'saccades a word for readers with central field loss (Rubin & Turano '
        '1994).',
  PresentationMode.shiftingWindow => 'A short window of words. Not built.',
  PresentationMode.continuousScroll =>
    'A line of text slides past a fixed mark. Read at much the same speed as '
        'one word at a time by visually impaired readers (Fine & Peli 1995), '
        'and ahead of it on comprehension in central vision loss '
        '(Akthar 2021).',
};

/// One line summarising how a profile reads, for a list row.
String describeProfile(ReadingProfile profile) => switch (profile.pacing.kind) {
  PacingModelKind.elicited => 'You advance each word',
  PacingModelKind.lengthScaled =>
    'Longer words held longer, ${profile.pacing.baseWpm.round()} wpm',
  PacingModelKind.constant =>
    '${profile.pacing.baseWpm.round()} words a minute',
};

/// How the pacing model behaves, in the reader's terms rather than the
/// engine's.
String describePacingKind(PacingModelKind kind) => switch (kind) {
  PacingModelKind.constant =>
    'Every word is held for the same time. Fastest for most readers with '
        'ordinary sight.',
  PacingModelKind.lengthScaled =>
    'Longer words are held longer. Carried readers with central field loss '
        'through sentences about a third faster in Aquilante 2001.',
  PacingModelKind.elicited =>
    'Nothing moves until you tap or press. Averaged 47% faster than a timed '
        'stream among slow low-vision readers in Arditi 1999.',
};
