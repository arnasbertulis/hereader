import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_tokens.dart';
import '../theme/appearance.dart';
import '../theme/content_width.dart';
import 'control_row.dart';
import 'custom_accent_screen.dart';
import 'info_dot.dart';
import 'section_header.dart';
import 'setting_slider.dart';

/// Identifies the screen-summary [InfoDot] in the AppBar's actions — see #430.
const Key appearanceInfoDotKey = Key('appearance-info-dot');

/// Identifies the Contrast section's header — see #430.
const Key appearanceContrastHeaderKey = Key('appearance-contrast-header');

/// Theme, accent, contrast and text size for app chrome.
///
/// Every control here retheme the whole app on the frame it is tapped, so
/// the screen is its own preview and carries none of the separate preview
/// surface the profile editor needs. That editor is previewing a reading
/// surface it is not currently standing on; this one is standing on what it
/// changes.
///
/// Reached from the settings index, which states the current theme and
/// accent on its Appearance row.
class AppearanceScreen extends StatelessWidget {
  final AppearanceController controller;

  const AppearanceScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance'),
        // Introduces all three sections below, so it lives on the screen's
        // own AppBar rather than trailing whichever section happens to be
        // last — see #343. InfoDot is a bare IconButton with no dependency
        // on SectionHeader, so it drops in unchanged.
        actions: const [
          InfoDot(
            key: appearanceInfoDotKey,
            semanticLabel: 'About appearance settings',
            explanation:
                'These four stay on this device. A phone read '
                'outdoors and a desktop in a dim room can want '
                'different ones.\n\n'
                'None of them touch the reading surface. The colours '
                'a word is drawn in belong to the reading profile you '
                'chose, under Reading profiles, and so does its size.',
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final settings = controller.settings;

          return ContentWidth(
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              children: [
                const SectionHeader('Theme'),
                for (final option in _themeOptions)
                  ControlRow(
                    icon: option.mode == settings.themeMode
                        ? AppIcons.chosen
                        : AppIcons.notChosen,
                    title: option.label,
                    supportingText: option.description,
                    selected: option.mode == settings.themeMode,
                    onTap: () => controller.setThemeMode(option.mode),
                  ),

                SectionHeader(
                  'Accent colour',
                  info: InfoDot(
                    semanticLabel: 'About accent colour',
                    explanation:
                        'Everything else stays grey, so the colour means '
                        'something wherever it appears.',
                  ),
                  supportingText:
                      'Used on buttons, selected rows and progress.',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final accent in AppAccents.all)
                        _AccentSwatch(
                          accent: accent,
                          selected: accent.color == settings.accent,
                          onTap: () => controller.setAccent(accent.color),
                        ),
                      // Selected when the stored colour is none of the six.
                      // The swatch shows that colour rather than a fixed
                      // sample, so the row reads as one set of choices with
                      // one of them selected.
                      _AccentSwatch(
                        accent: AppAccent('Custom', settings.accent),
                        selected: !AppAccents.all.any(
                          (a) => a.color == settings.accent,
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                CustomAccentScreen(controller: controller),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SectionHeader(
                  'Contrast',
                  key: appearanceContrastHeaderKey,
                ),
                ControlRow(
                  onTap: () =>
                      controller.setHighContrast(!settings.highContrast),
                  title: 'High contrast',
                  supportingText: 'Pure black and white surfaces.',
                  // A genuine trailing widget, not the InfoDot inside the
                  // tile's own title — see InfoDot's doc comment and #357's
                  // rule 4: that placement risks stealing the row's own tap.
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InfoDot(
                        semanticLabel: 'About high contrast',
                        explanation:
                            'Pure black and white surfaces, darker borders, '
                            'and thicker lines between them.\n\n'
                            'Your device may already ask for high contrast, '
                            'in which case the app follows it whether or not '
                            'this is on.',
                      ),
                      Switch(
                        value: settings.highContrast,
                        onChanged: controller.setHighContrast,
                      ),
                    ],
                  ),
                ),

                SectionHeader(
                  'Text size',
                  info: InfoDot(
                    semanticLabel: 'About text size',
                    explanation:
                        'Scales labels, dialogs and every other piece of '
                        'text outside the reading surface.\n\n'
                        'The RSVP word has its own size, set from the '
                        'reading profile you chose.',
                  ),
                ),
                SettingSlider(
                  label: 'Chrome text size',
                  valueLabel: '${(settings.chromeTextScale * 100).round()}%',
                  value: settings.chromeTextScale,
                  min: chromeTextScaleMin,
                  max: chromeTextScaleMax,
                  divisions: ((chromeTextScaleMax - chromeTextScaleMin) / 0.05)
                      .round(),
                  onChanged: controller.setChromeTextScale,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ThemeOption {
  final ThemeMode mode;
  final String label;
  final String description;

  const _ThemeOption(this.mode, this.label, this.description);
}

const _themeOptions = [
  _ThemeOption(
    ThemeMode.system,
    'Match my device',
    'Changes with your system setting.',
  ),
  _ThemeOption(ThemeMode.light, 'Light', 'Dark text on a pale surface.'),
  _ThemeOption(ThemeMode.dark, 'Dark', 'Pale text on a dark surface.'),
];

/// One accent, as a filled circle with its name under it.
///
/// The check mark is why the name is there too: a swatch that signalled
/// selection by colour alone would be unreadable to the reader this app is
/// for, and to anyone whose accent choice is close to the one beside it.
class _AccentSwatch extends StatelessWidget {
  final AppAccent accent;
  final bool selected;
  final VoidCallback onTap;

  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      label: accent.name,
      // One node rather than a button and a stray label beside it. The
      // reading surface does the same thing for the same reason.
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? scheme.onSurface : scheme.outline,
                    width: selected
                        ? AppHairline.widthHighContrast
                        : AppHairline.width,
                  ),
                ),
                child: selected
                    ? Icon(AppIcons.confirm, color: onAccent(accent.color))
                    : null,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(accent.name, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
