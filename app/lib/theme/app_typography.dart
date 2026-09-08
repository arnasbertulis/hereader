import 'package:flutter/material.dart';

/// The type scale for app chrome — four roles, expressed as ratios of a
/// 16-logical-pixel base, per ADR 0031.
///
/// **Known gap, stated rather than hidden:** the brief specifies Atkinson
/// Hyperlegible Next, bundled as an asset under `app/assets/fonts/`, two
/// weights (400 and 600). That font file is not in this repository yet — I
/// have no way to fetch and verify a licensed font asset from here, and
/// shipping a `fonts:` entry in `pubspec.yaml` that points at a file that
/// does not exist would fail the build rather than degrade gracefully. So
/// [appTextTheme] below sets every size, weight and line height from the
/// brief's table and leaves `fontFamily` on the platform default. Dropping
/// in the real font is: add the two weight files under
/// `app/assets/fonts/`, declare the `fonts:` section in `pubspec.yaml`, and
/// set [_fontFamily] to the family name. Nothing else in this file needs to
/// change.
///
/// Percentages and word counts should use `FontFeature.tabularFigures()` at
/// the call site, so a readout does not shift width as it counts. Left to
/// the call site rather than baked into a text style here, since only some
/// uses of `bodyLarge`/`labelSmall` are numeric readouts.
const String? _fontFamily = null;

/// ADR 0031 section 3: every `TextTheme` slot the app or a component theme
/// can resolve is declared here, aliased onto one of the four roles below.
/// A partial `TextTheme` merges onto `Typography`'s Material 3 defaults
/// rather than replacing them, so an undeclared slot silently reappears at
/// Material's size, weight and letter-spacing — the defect this ADR closes.
/// `displayLarge`, `displayMedium`, `displaySmall`, `headlineLarge` and
/// `headlineMedium` are omitted: zero call sites resolve any of them (About's
/// app name uses the Screen title role instead), and no component theme in
/// this app defaults to them.
///
/// [scale] is the reader's chrome text-size choice from Appearance (#338),
/// a multiple of the sizes below — ADR 0031 states every role as a ratio of
/// a 16px base for exactly this reason, so one lever moves every size in
/// this table together rather than the call sites needing to know about it
/// individually.
TextTheme appTextTheme(ColorScheme scheme, {double scale = 1.0}) {
  TextStyle style({
    required double size,
    required FontWeight weight,
    required double height,
    Color? color,
  }) => TextStyle(
    fontFamily: _fontFamily,
    fontSize: size * scale,
    fontWeight: weight,
    height: height,
    color: color ?? scheme.onSurface,
  );

  // ADR 0031 section 1: four roles, expressed as ratios of a 16px base —
  // one lever moves the whole scale.
  const base = 16.0;
  final screenTitle = style(
    size: base * 1.5,
    weight: FontWeight.w600,
    height: 1.25,
  );
  final sectionHeader = style(
    size: base * 1.25,
    weight: FontWeight.w600,
    height: 1.30,
    color: scheme.onSurfaceVariant,
  );
  final rowLabel = style(size: base, weight: FontWeight.w600, height: 1.30);
  final secondary = style(
    size: base,
    weight: FontWeight.w400,
    height: 1.45,
    color: scheme.onSurfaceVariant,
  );

  // ADR 0031 section 2: nothing sits below the base. There is no 14 tier
  // and no 12 tier — every slot below resolves to one of the four styles
  // above rather than to a smaller size of its own.
  return TextTheme(
    headlineSmall: screenTitle,
    titleLarge: sectionHeader,
    titleMedium: rowLabel,
    titleSmall: rowLabel,
    bodyLarge: secondary,
    bodyMedium: secondary,
    bodySmall: secondary,
    labelLarge: rowLabel,
    labelMedium: secondary,
    labelSmall: secondary,
  );
}
