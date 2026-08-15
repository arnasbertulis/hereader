import 'package:flutter/material.dart';

/// The type scale for app chrome, per section 3.2 of the UI brief.
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
/// uses of `bodyMedium`/`labelSmall` are numeric readouts.
const String? _fontFamily = null;

TextTheme appTextTheme(ColorScheme scheme) {
  TextStyle style({
    required double size,
    required FontWeight weight,
    required double height,
  }) => TextStyle(
    fontFamily: _fontFamily,
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: scheme.onSurface,
  );

  return TextTheme(
    displaySmall: style(size: 32, weight: FontWeight.w600, height: 1.20),
    headlineSmall: style(size: 24, weight: FontWeight.w600, height: 1.25),
    titleMedium: style(size: 16, weight: FontWeight.w600, height: 1.30),
    bodyLarge: style(size: 16, weight: FontWeight.w400, height: 1.45),
    bodyMedium: style(size: 14, weight: FontWeight.w400, height: 1.45),
    labelLarge: style(size: 14, weight: FontWeight.w600, height: 1.20),
    labelMedium: style(size: 12, weight: FontWeight.w600, height: 1.20),
    labelSmall: style(size: 12, weight: FontWeight.w400, height: 1.20),
  );
}
