import 'package:app/theme/app_colors.dart';
import 'package:app/theme/app_theme.dart';
import 'package:app/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// #338: `scale` is the one lever ADR 0031 states every chrome role as a
/// ratio of a 16px base for. These expected values are literal, worked out
/// by hand from the sizes `app_typography.dart` declares — 16, 24 and 32 —
/// rather than recomputed the way [appTextTheme] computes them, so a bug in
/// the multiplication itself would still fail the test.
void main() {
  final scheme = buildScheme(
    accent: AppAccents.defaultAccent.color,
    brightness: Brightness.light,
    highContrast: false,
  );

  test('defaults to the declared sizes unscaled', () {
    final theme = appTextTheme(scheme);

    expect(theme.bodyLarge!.fontSize, 16);
    expect(theme.titleMedium!.fontSize, 16);
    expect(theme.headlineSmall!.fontSize, 24);
    expect(theme.displaySmall!.fontSize, 32);
  });

  test('scales every role by the same multiple', () {
    final theme = appTextTheme(scheme, scale: 1.25);

    expect(theme.bodyLarge!.fontSize, 20);
    expect(theme.titleMedium!.fontSize, 20);
    expect(theme.headlineSmall!.fontSize, 30);
    expect(theme.displaySmall!.fontSize, 40);
  });

  test('a scale below 1.0 shrinks every role by the same multiple', () {
    final theme = appTextTheme(scheme, scale: 0.85);

    expect(theme.bodyLarge!.fontSize, closeTo(13.6, 0.001));
    expect(theme.titleMedium!.fontSize, closeTo(13.6, 0.001));
  });

  test('appTheme threads textScale through to its TextTheme', () {
    final theme = appTheme(brightness: Brightness.light, textScale: 1.25);

    expect(theme.textTheme.bodyLarge!.fontSize, 20);
  });

  test('appTheme defaults textScale to 1.0', () {
    final theme = appTheme(brightness: Brightness.light);

    expect(theme.textTheme.bodyLarge!.fontSize, 16);
  });
}
