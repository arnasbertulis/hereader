import 'package:app/theme/app_colors.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// Every scheme the app can build, measured.
///
/// Six accents by two brightnesses by two contrast levels. The accent
/// becomes a reader setting in this change, so all twenty-four are reachable
/// where before only one was, and a palette nobody can read is not something
/// to find out about from a reader.
///
/// The ratio maths itself is tested in `rsvp_engine`, under `dart2js` as
/// well as the VM. This file only builds `ColorScheme`s, which needs
/// Flutter, so it stays here.

double _ratio(Color foreground, Color background) =>
    contrastRatio(foreground.toARGB32(), background.toARGB32());

/// The roles a screen can put content on. Named rather than iterated so a
/// failure says which surface it was.
Map<String, Color> _surfaceRoles(ColorScheme scheme) => {
  'surfaceContainerLowest': scheme.surfaceContainerLowest,
  'surface': scheme.surface,
  'surfaceBright': scheme.surfaceBright,
  'surfaceContainerLow': scheme.surfaceContainerLow,
  'surfaceContainer': scheme.surfaceContainer,
  'surfaceContainerHigh': scheme.surfaceContainerHigh,
  'surfaceContainerHighest': scheme.surfaceContainerHighest,
  'surfaceDim': scheme.surfaceDim,
};

void main() {
  for (final accent in AppAccents.all) {
    for (final brightness in Brightness.values) {
      for (final highContrast in [false, true]) {
        final label =
            '${accent.name}, ${brightness.name}'
            '${highContrast ? ', high contrast' : ''}';

        group(label, () {
          final scheme = buildScheme(
            accent: accent.color,
            brightness: brightness,
            highContrast: highContrast,
          );

          _surfaceRoles(scheme).forEach((name, surface) {
            test('onSurface reads on $name', () {
              expect(
                _ratio(scheme.onSurface, surface),
                greaterThanOrEqualTo(4.5),
              );
            });

            // The secondary text role, used for subtitles and captions.
            // Held to the same bar as primary text rather than to WCAG's
            // large-text exception: this app is for readers who cannot rely
            // on a page, and a caption they cannot read is a caption that
            // may as well not be there.
            test('onSurfaceVariant reads on $name', () {
              expect(
                _ratio(scheme.onSurfaceVariant, surface),
                greaterThanOrEqualTo(4.5),
              );
            });

            // 3:1, not 4.5:1. Outline is not text; it draws the border of
            // an outlined button, which WCAG 1.4.11 treats as information
            // needed to identify a control. Nothing here uses elevation, so
            // that border is the only thing separating the control from the
            // surface behind it.
            test('outline separates a control from $name', () {
              expect(_ratio(scheme.outline, surface), greaterThanOrEqualTo(3));
            });
          });

          test('the accent pair reads', () {
            expect(
              _ratio(scheme.onPrimary, scheme.primary),
              greaterThanOrEqualTo(4.5),
            );
            expect(
              _ratio(scheme.onPrimaryContainer, scheme.primaryContainer),
              greaterThanOrEqualTo(4.5),
            );
          });

          test('the inverse pair reads, for snack bars and tooltips', () {
            expect(
              _ratio(scheme.onInverseSurface, scheme.inverseSurface),
              greaterThanOrEqualTo(4.5),
            );
          });
        });
      }
    }
  }

  group('the ramp does not follow the accent', () {
    for (final brightness in Brightness.values) {
      for (final highContrast in [false, true]) {
        final label =
            '${brightness.name}'
            '${highContrast ? ', high contrast' : ''}';

        test('identical greys under every accent — $label', () {
          ColorScheme schemeFor(AppAccent accent) => buildScheme(
            accent: accent.color,
            brightness: brightness,
            highContrast: highContrast,
          );

          final first = schemeFor(AppAccents.all.first);

          for (final accent in AppAccents.all.skip(1)) {
            final scheme = schemeFor(accent);

            expect(
              _surfaceRoles(scheme),
              _surfaceRoles(first),
              reason: '${accent.name} tinted a surface role',
            );
            expect(scheme.onSurface, first.onSurface);
            expect(scheme.onSurfaceVariant, first.onSurfaceVariant);
            expect(scheme.outline, first.outline);
            expect(scheme.outlineVariant, first.outlineVariant);
          }
        });

        test('the accent still differs between accents — $label', () {
          final ink = buildScheme(
            accent: AppAccents.ink.color,
            brightness: brightness,
            highContrast: highContrast,
          );
          final rust = buildScheme(
            accent: AppAccents.rust.color,
            brightness: brightness,
            highContrast: highContrast,
          );

          expect(ink.primary, isNot(rust.primary));
        });
      }
    }
  });

  group('accent swatches', () {
    // The check mark that says which swatch is selected, since colour alone
    // cannot carry that.
    for (final accent in AppAccents.all) {
      test('the check mark reads on ${accent.name}', () {
        expect(
          _ratio(onAccent(accent.color), accent.color),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });

  group('appTheme', () {
    test('falls back to the default accent', () {
      final fallback = appTheme(brightness: Brightness.light);
      final explicit = appTheme(
        brightness: Brightness.light,
        accent: AppAccents.defaultAccent.color,
      );

      expect(fallback.colorScheme.primary, explicit.colorScheme.primary);
    });

    test('hairlines thicken at high contrast', () {
      final normal = appTheme(brightness: Brightness.light);
      final high = appTheme(brightness: Brightness.light, highContrast: true);

      expect(
        high.dividerTheme.thickness,
        greaterThan(normal.dividerTheme.thickness!),
      );
    });

    // Elevation is the thing hairlines replace. A shadow is a blur, blur
    // rasterises, and raster is back on the main thread on web until
    // cross-origin isolation ships.
    test('nothing carries elevation', () {
      final theme = appTheme(brightness: Brightness.light);

      expect(theme.appBarTheme.elevation, 0);
      expect(theme.appBarTheme.scrolledUnderElevation, 0);
      expect(theme.cardTheme.elevation, 0);
      expect(theme.navigationBarTheme.elevation, 0);
    });
  });
}
