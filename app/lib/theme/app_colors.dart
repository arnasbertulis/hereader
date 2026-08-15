import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// Neutral surface ramps and the accent list, and [buildScheme], which
/// combines them into a [ColorScheme].
///
/// The problem this file exists to solve is not the seed hue. It is that
/// `ColorScheme.fromSeed`'s default `tonalSpot` variant tints every surface
/// with the seed colour rather than producing a grey app with coloured
/// buttons — a deep seed gives a pale wash on every card, sheet and bar,
/// which is the tell that read as "generic Material app" more than the
/// purple ever did. So the scheme is built in two parts: `fromSeed` with the
/// `fidelity` variant generates the accent group, keeping the accent close
/// to the colour the reader actually picked rather than pulling it toward a
/// pastel, and every surface and outline role is then overridden with a
/// fixed neutral ramp that does not move with the accent.

/// A named accent choice. The reading-background colour picker in
/// `profile_edit_screen.dart` already exists for a not-quite-arbitrary RGB
/// choice; this list is reused there rather than duplicated when a "Custom"
/// accent is added in the appearance screen (PR 4). Deliberately excludes
/// purple: `AppAccents.ink` replaces the old Material baseline seed, so the
/// chrome does not merely change hue, it stops tinting every surface with
/// one.
class AppAccent {
  final String name;
  final Color color;

  const AppAccent(this.name, this.color);
}

abstract final class AppAccents {
  static const ink = AppAccent('Ink', Color(0xFF2F4858));
  static const teal = AppAccent('Teal', Color(0xFF14746F));
  static const moss = AppAccent('Moss', Color(0xFF4E6E4E));
  static const amber = AppAccent('Amber', Color(0xFFA8791C));
  static const rust = AppAccent('Rust', Color(0xFFA9552F));
  static const crimson = AppAccent('Crimson', Color(0xFF9B3A3A));

  /// Ink is the default until appearance preferences (PR 4) let a reader
  /// choose one of the others, or a custom colour.
  static const defaultAccent = ink;

  static const all = [ink, teal, moss, amber, rust, crimson];
}

/// The mark drawn on top of a filled accent swatch.
///
/// Black or white by the accent's own luminance, using the same 0.179
/// threshold as `chromeBrightnessFor`: that is the point where a colour's
/// contrast against black equals its contrast against white, so it is where
/// the better choice flips. The swatch is the one place the raw accent hex
/// is painted rather than handed to `fromSeed`, and a selected swatch has to
/// show a check rather than relying on colour alone.
Color onAccent(Color accent) =>
    relativeLuminance(accent.toARGB32()) > 0.179
    ? const Color(0xFF000000)
    : const Color(0xFFFFFFFF);

/// The fixed neutral roles [buildScheme] overrides `fromSeed`'s output with.
///
/// Neither end of the ramp is pure black or pure white, for the same reason
/// `profile_presentation.dart` gives for the reading surface itself: maximum
/// contrast is uncomfortable over a long session. The values here sit close
/// to that file's `lightSurfaceArgb` (`0xFFFAFAFA`) and `darkInkArgb`
/// (`0xFF121212`) on purpose, so a reader who tinted nothing sees one
/// continuous surface on leaving a book rather than a visible seam between
/// reading surface and chrome.
class _Neutrals {
  final Color surfaceContainerLowest;
  final Color surface;
  final Color surfaceBright;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color surfaceDim;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color inverseSurface;
  final Color onInverseSurface;

  const _Neutrals({
    required this.surfaceContainerLowest,
    required this.surface,
    required this.surfaceBright,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.surfaceDim,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.inverseSurface,
    required this.onInverseSurface,
  });

  /// Applies only the roles a high-contrast override supplies, keeping the
  /// base ramp for everything the UI brief's high-contrast table did not
  /// name (`surfaceContainerLowest`, `surfaceBright`, `surfaceDim`, the two
  /// inverse roles, and the container steps other than `surfaceContainer`).
  /// Flagged rather than guessed at: those roles want a real accessibility
  /// pass before being called complete, and inheriting the standard ramp is
  /// the safer default in the meantime, since it is at minimum the ratio
  /// already verified in the contrast test suite.
  _Neutrals overrideWith({
    required Color surface,
    required Color onSurface,
    required Color onSurfaceVariant,
    required Color outline,
    required Color outlineVariant,
    required Color surfaceContainer,
  }) => _Neutrals(
    surfaceContainerLowest: surfaceContainerLowest,
    surface: surface,
    surfaceBright: surfaceBright,
    surfaceContainerLow: surfaceContainerLow,
    surfaceContainer: surfaceContainer,
    surfaceContainerHigh: surfaceContainerHigh,
    surfaceContainerHighest: surfaceContainerHighest,
    surfaceDim: surfaceDim,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    outlineVariant: outlineVariant,
    inverseSurface: inverseSurface,
    onInverseSurface: onInverseSurface,
  );
}

/// `outline` is darker than the rest of the ramp implies, and deliberately.
///
/// It is not text; it draws the border of an outlined button, which WCAG
/// 1.4.11 treats as information needed to identify a control and asks for
/// 3:1 against what it sits on. The value this started at reached 3.05
/// against `surface` and 2.52 against `surfaceContainerHighest`, so a button
/// on a card missed the bar. Nothing here uses elevation, so that border is
/// the only thing separating the control from the surface behind it.
/// `app/test/app_theme_test.dart` measures it against every surface role.
const _lightNeutrals = _Neutrals(
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surface: Color(0xFFFBFBFC),
  surfaceBright: Color(0xFFFBFBFC),
  surfaceContainerLow: Color(0xFFF5F6F7),
  surfaceContainer: Color(0xFFEFF1F2),
  surfaceContainerHigh: Color(0xFFE9EBED),
  surfaceContainerHighest: Color(0xFFE3E6E8),
  surfaceDim: Color(0xFFDCDFE1),
  onSurface: Color(0xFF16181A),
  onSurfaceVariant: Color(0xFF5A6066),
  outline: Color(0xFF787E82),
  outlineVariant: Color(0xFFD5D9DC),
  inverseSurface: Color(0xFF2B2F33),
  onInverseSurface: Color(0xFFF1F3F4),
);

const _darkNeutrals = _Neutrals(
  surfaceContainerLowest: Color(0xFF0D0F10),
  surface: Color(0xFF121416),
  surfaceBright: Color(0xFF35383B),
  surfaceContainerLow: Color(0xFF191B1D),
  surfaceContainer: Color(0xFF1D2022),
  surfaceContainerHigh: Color(0xFF272A2D),
  surfaceContainerHighest: Color(0xFF323538),
  surfaceDim: Color(0xFF101213),
  onSurface: Color(0xFFE6E8EA),
  onSurfaceVariant: Color(0xFFA9B0B5),
  outline: Color(0xFF7C8388),
  outlineVariant: Color(0xFF33373A),
  inverseSurface: Color(0xFFE6E8EA),
  onInverseSurface: Color(0xFF1A1C1E),
);

_Neutrals _neutrals(Brightness brightness, bool highContrast) {
  final base = brightness == Brightness.light ? _lightNeutrals : _darkNeutrals;
  if (!highContrast) return base;

  return brightness == Brightness.light
      ? base.overrideWith(
          surface: const Color(0xFFFFFFFF),
          onSurface: const Color(0xFF000000),
          onSurfaceVariant: const Color(0xFF2A2E31),
          outline: const Color(0xFF4A4F53),
          outlineVariant: const Color(0xFF767C80),
          surfaceContainer: const Color(0xFFEDEEEF),
        )
      : base.overrideWith(
          surface: const Color(0xFF000000),
          onSurface: const Color(0xFFFFFFFF),
          onSurfaceVariant: const Color(0xFFD6DADD),
          outline: const Color(0xFFA8AEB2),
          outlineVariant: const Color(0xFF767C80),
          surfaceContainer: const Color(0xFF141516),
        );
}

/// Builds the scheme every app-chrome screen themes from.
///
/// `fromSeed` supplies the accent group (`primary`, `secondary`, `tertiary`
/// and their `on*`/container pairs); every surface and outline role is then
/// overridden from [_neutrals], so the same greys appear under every accent
/// and the accent is visible only where section 2 of the UI brief says it
/// should be: the active nav indicator, progress fill, primary buttons,
/// selected states and focus rings.
ColorScheme buildScheme({
  required Color accent,
  required Brightness brightness,
  required bool highContrast,
}) {
  final seeded = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    contrastLevel: highContrast ? 1.0 : 0.0,
  );
  final n = _neutrals(brightness, highContrast);

  return seeded.copyWith(
    surfaceContainerLowest: n.surfaceContainerLowest,
    surface: n.surface,
    surfaceBright: n.surfaceBright,
    surfaceContainerLow: n.surfaceContainerLow,
    surfaceContainer: n.surfaceContainer,
    surfaceContainerHigh: n.surfaceContainerHigh,
    surfaceContainerHighest: n.surfaceContainerHighest,
    surfaceDim: n.surfaceDim,
    onSurface: n.onSurface,
    onSurfaceVariant: n.onSurfaceVariant,
    outline: n.outline,
    outlineVariant: n.outlineVariant,
    inverseSurface: n.inverseSurface,
    onInverseSurface: n.onInverseSurface,
  );
}
