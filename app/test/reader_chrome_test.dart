import 'package:app/reading/profile_presentation.dart';
import 'package:app/theme/app_colors.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// What the controls on the reading surface are drawn in, measured.
///
/// `app_theme_test.dart` measures the app's own scheme against its own ramp,
/// which is a closed set of colours. This file measures the other case: a
/// glyph drawn straight onto a background the reader picked, which the
/// background field in `profile_edit_screen.dart` accepts as arbitrary RGB.
///
/// The bar is WCAG 1.4.11's 3:1 rather than 4.5:1. Nothing on the reading
/// surface is text after ADR 0015 — the play button's label came off with
/// the same change — and 1.4.11 is the clause covering a control that has to
/// be identifiable.

double _ratio(int foreground, int background) =>
    contrastRatio(foreground, background);

/// Backgrounds a reader can reach. The two polarity defaults, every preset,
/// and tints picked to sit either side of the 0.179 flip and on it.
Map<String, PresentationConfig> _backgrounds() => {
  'dark on light, untinted': const PresentationConfig(),
  'light on dark, untinted': const PresentationConfig(
    polarity: Polarity.lightOnDark,
  ),
  for (final preset in Presets.all) preset.name: preset.presentation,
  // Mid greys either side of the flip, and one as close to it as an
  // 8-bit channel reaches. The last is the worst case the ink can face:
  // no overlay contrasts well with a background at that luminance.
  'tint below the flip': const PresentationConfig(tintArgb: 0xFF6E6E6E),
  'tint on the flip': const PresentationConfig(tintArgb: 0xFF777777),
  'tint above the flip': const PresentationConfig(tintArgb: 0xFF808080),
  // Saturated, because a mid grey and a mid colour of the same luminance
  // are not the same problem for a reader.
  'saturated warm tint': const PresentationConfig(tintArgb: 0xFF8A5A2B),
  'saturated cool tint': const PresentationConfig(tintArgb: 0xFF2B4A8A),
};

void main() {
  group('chrome ink on the reading surface', () {
    _backgrounds().forEach((name, presentation) {
      test('a glyph is identifiable on $name', () {
        expect(
          _ratio(readerInkArgbFor(presentation), surfaceArgbFor(presentation)),
          greaterThanOrEqualTo(3),
        );
      });
    });

    test('the ink follows luminance rather than polarity', () {
      // A reader on dark-on-light who tints the background near black. The
      // text stays dark and becomes hard to read, which `rateContrast`
      // warns about and does not block. The chrome is not part of that
      // choice and has to stay legible regardless.
      const tinted = PresentationConfig(
        polarity: Polarity.darkOnLight,
        tintArgb: 0xFF101010,
      );

      expect(inkArgbFor(tinted.polarity), darkInkArgb);
      expect(readerInkArgbFor(tinted), lightInkArgb);
    });

    test('an untinted profile draws chrome in the reading ink', () {
      // The point of reusing the reading ink values rather than defining a
      // second pair: nothing about the surface changes when the reader's
      // eye moves from the word to the controls.
      for (final polarity in Polarity.values) {
        final presentation = PresentationConfig(polarity: polarity);

        expect(
          readerInkArgbFor(presentation),
          inkArgbFor(polarity),
          reason: '${polarity.name} split the two inks',
        );
      }
    });
  });

  group('readerChromeTheme', () {
    ThemeData themeFor(
      PresentationConfig presentation, {
      Color? accent,
      bool highContrast = false,
    }) => readerChromeTheme(
      presentation: presentation,
      accent: accent ?? AppAccents.defaultAccent.color,
      highContrast: highContrast,
    );

    test('panels take the app ramp rather than a seeded surface', () {
      // The whole failure this replaced: `ColorScheme.fromSeed` tints every
      // surface role with its seed, so the chapter panel and the profile
      // sheet came out coloured. These roles have to be the same greys the
      // library list is drawn on.
      for (final polarity in Polarity.values) {
        final presentation = PresentationConfig(polarity: polarity);
        final scheme = themeFor(presentation).colorScheme;
        final app = buildScheme(
          accent: AppAccents.defaultAccent.color,
          brightness: chromeBrightnessFor(presentation),
          highContrast: false,
        );

        expect(scheme.surface, app.surface);
        expect(scheme.surfaceContainerHigh, app.surfaceContainerHigh);
        expect(scheme.onSurface, app.onSurface);
        expect(scheme.outlineVariant, app.outlineVariant);
      }
    });

    test('the greys do not move with the accent', () {
      const presentation = PresentationConfig();

      final ink = themeFor(presentation, accent: AppAccents.ink.color);
      final rust = themeFor(presentation, accent: AppAccents.rust.color);

      expect(ink.colorScheme.surface, rust.colorScheme.surface);
      expect(ink.colorScheme.onSurface, rust.colorScheme.onSurface);
      // The accent still arrives, on the one role that uses it.
      expect(ink.colorScheme.primary, isNot(rust.colorScheme.primary));
    });

    test('brightness comes from the profile, not the platform', () {
      // A book read light on dark keeps a dark panel over it whatever the
      // device is set to, because nothing here reads the platform at all.
      const light = PresentationConfig();
      const dark = PresentationConfig(polarity: Polarity.lightOnDark);

      expect(themeFor(light).colorScheme.brightness, Brightness.light);
      expect(themeFor(dark).colorScheme.brightness, Brightness.dark);
    });

    test('the scaffold matches the profile so no edge shows through', () {
      const presentation = PresentationConfig(tintArgb: 0xFF2B4A8A);

      expect(
        themeFor(presentation).scaffoldBackgroundColor.toARGB32(),
        surfaceArgbFor(presentation),
      );
    });

        test('the fill reads against its track on every reachable background', () {
      for (final accent in AppAccents.all) {
        for (final entry in _backgrounds().entries) {
          final presentation = entry.value;
          final fill = readerProgressFillFor(
            scheme: themeFor(presentation, accent: accent.color).colorScheme,
            presentation: presentation,
          );

          expect(
            _ratio(fill.toARGB32(), readerTrackFor(presentation).toARGB32()),
            greaterThanOrEqualTo(readerMinControlContrast),
            reason: '${accent.name} on ${entry.key}',
          );
        }
      }
    });

    test('the accent survives the backgrounds a reader is likely to use', () {
      // The guard exists for tints near the 0.179 flip, where nothing
      // contrasts with a mid-luminance track. It must not be quietly
      // swallowing the accent on the profiles the app actually ships.
      for (final accent in AppAccents.all) {
        for (final preset in Presets.all) {
          final scheme = themeFor(
            preset.presentation,
            accent: accent.color,
          ).colorScheme;

          expect(
            readerProgressFillFor(
              scheme: scheme,
              presentation: preset.presentation,
            ),
            scheme.primary,
            reason: '${accent.name} fell back to the ink on ${preset.name}',
          );
        }
      }
    });

    test('the track separates from the surface without becoming a bar', () {
      // Low enough to read as a groove, high enough to be there at all.
      for (final presentation in _backgrounds().values) {
        final ratio = _ratio(
          readerTrackFor(presentation).toARGB32(),
          surfaceArgbFor(presentation),
        );

        expect(ratio, greaterThan(1.2));
        expect(ratio, lessThan(2));
      }
    });


    test('hairlines thicken at high contrast', () {
      const presentation = PresentationConfig();

      expect(
        themeFor(presentation, highContrast: true).dividerTheme.thickness,
        greaterThan(themeFor(presentation).dividerTheme.thickness!),
      );
    });

    test('panels carry no elevation', () {
      // Elevation is the thing hairlines replace, and a blurred shadow
      // rasterises on the main thread on web.
      final theme = themeFor(const PresentationConfig());

      expect(theme.drawerTheme.elevation, 0);
      expect(theme.bottomSheetTheme.elevation, 0);
    });
  });

  group('AppChromeSource', () {
    test('appTheme carries the accent as the reader picked it', () {
      // `buildScheme` maps the accent through `fidelity`, so `primary` is
      // not the value that went in. The reader screen needs the original,
      // because it builds its own scheme at its own brightness.
      final theme = appTheme(
        brightness: Brightness.light,
        accent: AppAccents.rust.color,
      );
      final source = theme.extension<AppChromeSource>();

      expect(source?.accent, AppAccents.rust.color);
      expect(source?.highContrast, isFalse);
    });

    test('the high contrast themes report it', () {
      // How a reader who set high contrast at the operating system level
      // reaches the reading surface: MaterialApp picks `highContrastTheme`
      // and the extension on it says so.
      final theme = appTheme(
        brightness: Brightness.dark,
        accent: AppAccents.teal.color,
        highContrast: true,
      );

      expect(theme.extension<AppChromeSource>()?.highContrast, isTrue);
    });

    testWidgets('a subtree with no extension falls back to the default', (
      tester,
    ) async {
      late AppChromeSource read;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Builder(
            builder: (context) {
              read = AppChromeSource.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(read.accent, AppAccents.defaultAccent.color);
      expect(read.highContrast, isFalse);
    });
  });

  group('the profile sheet', () {
    testWidgets('the container matches its contents under a dark app theme', (
      tester,
    ) async {
      // The mismatch this covers: a light reading profile under a dark app
      // theme. `showModalBottomSheet` resolves the container against the
      // call site, which sits above the reader's own Theme, so the two came
      // out of different brightnesses.
      const presentation = PresentationConfig();
      final chrome = readerChromeTheme(
        presentation: presentation,
        accent: AppAccents.defaultAccent.color,
        highContrast: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(brightness: Brightness.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: chrome.bottomSheetTheme.backgroundColor,
                  elevation: chrome.bottomSheetTheme.elevation,
                  shape: chrome.bottomSheetTheme.shape,
                  builder: (_) => Theme(
                    data: chrome,
                    child: const ListTile(title: Text('Standard')),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final material = tester.widget<Material>(
        find
            .ancestor(
              of: find.text('Standard'),
              matching: find.byType(Material),
            )
            .first,
      );

      expect(material.color, chrome.colorScheme.surface);

      // And the pair on it reads, which is the thing the reader notices
      // when the container and its contents disagree.
      final label = tester.widget<Text>(find.text('Standard'));
      final style = label.style ?? chrome.textTheme.bodyLarge!;

      expect(
        contrastRatio(
          (style.color ?? chrome.colorScheme.onSurface).toARGB32(),
          chrome.colorScheme.surface.toARGB32(),
        ),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}
