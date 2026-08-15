import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// Turning a [ReadingProfile] into things a screen can show, and the single
/// home for colour in this app.
///
/// The engine stores colours as ARGB integers so it stays free of Flutter.
/// Everything that maps those to real colours, judges whether the result is
/// legible, builds a theme from them, or writes a profile out in words
/// belongs here rather than in a widget.

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
int surfaceArgbFor(PresentationConfig presentation) =>
    presentation.tintArgb ??
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
// `hereaderSeed` and `appTheme` moved to `app_theme.dart` in the UI pass:
// ordinary app chrome now has a real, configurable accent (see the theme
// pass's `buildScheme`), and that accent must never leak onto the reading
// surface — a reader who tinted their background moss and set the app
// accent to rust would otherwise see the two adjacent on the one screen
// where the whole point is that they chose the colours.

/// The seed [readerChromeTheme] derives from. Fixed, and never the app's
/// configurable accent, for the reason above.
const readerChromeSeed = Color(0xFF6750A4);

/// Whether controls drawn over this profile's reading surface should be
/// light or dark.
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
Brightness chromeBrightnessFor(PresentationConfig presentation) =>
    relativeLuminance(surfaceArgbFor(presentation)) > 0.179
    ? Brightness.light
    : Brightness.dark;

/// A theme for the controls the reader screen stacks on its surface.
///
/// The chapter button, the playback controls, the progress bar and the front
/// matter offer are drawn directly on top of the text. Without this they take
/// the app's theme, so both central field loss presets — `lightOnDark` — put
/// a light panel and four light tonal buttons over a near-black surface,
/// which is the opposite of what choosing reverse polarity asks for.
///
/// `scaffoldBackgroundColor` matches the profile so nothing shows through at
/// the edges during a route transition. `colorScheme.surface` is left as the
/// seed produced it: forcing the profile's tint in would carry `onSurface`
/// along with it, and a saturated background would then render the panel's
/// own text unreadable at exactly the tints a reader is most likely to pick
/// deliberately.
ThemeData readerChromeTheme(PresentationConfig presentation) {
  final brightness = chromeBrightnessFor(presentation);

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: readerChromeSeed,
      brightness: brightness,
    ),
    scaffoldBackgroundColor: colorOf(surfaceArgbFor(presentation)),
  );
}

// -- descriptions -------------------------------------------------------

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
  final display = referenceDisplay(profile.pacing);
  if (display == null) return null;

  final fade = profile.presentation.transitionMs;
  if (fade <= display.inMilliseconds) return null;

  return 'Longer than the ${display.inMilliseconds} ms each word is shown, '
      'so words will overlap as one fades into the next.';
}

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
