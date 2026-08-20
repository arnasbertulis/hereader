import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_tokens.dart';
import '../theme/appearance.dart';
import 'custom_accent_screen.dart';

/// Theme, accent and contrast for app chrome.
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
      appBar: AppBar(title: const Text('Appearance')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final settings = controller.settings;
          final theme = Theme.of(context);

          return ListView(
            children: [
              const _SectionHeader('Theme'),
              for (final option in _themeOptions)
                ListTile(
                  leading: Icon(
                    option.mode == settings.themeMode
                        ? AppIcons.chosen
                        : AppIcons.notChosen,
                  ),
                  title: Text(option.label),
                  subtitle: Text(option.description),
                  selected: option.mode == settings.themeMode,
                  onTap: () => controller.setThemeMode(option.mode),
                ),

              const _SectionHeader('Accent colour'),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text(
                  'Used on buttons, selected rows and progress. Everything '
                  'else stays grey, so the colour means something wherever '
                  'it appears.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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

              const _SectionHeader('Contrast'),
              SwitchListTile(
                value: settings.highContrast,
                onChanged: controller.setHighContrast,
                title: const Text('High contrast'),
                subtitle: const Text(
                  'Pure black and white surfaces, darker borders, and '
                  'thicker lines between them.',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  0,
                ),
                child: Text(
                  'Your device may already ask for high contrast, in which '
                  'case the app follows it whether or not this is on.',
                  style: theme.textTheme.bodySmall,
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                child: Text(
                  'These three stay on this device. A phone read outdoors '
                  'and a desktop in a dim room can want different ones.\n\n'
                  'None of them touch the reading surface. The colours a '
                  'word is drawn in belong to the reading profile you chose, '
                  'under Reading profiles.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
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

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.xl,
      AppSpacing.lg,
      AppSpacing.sm,
    ),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}
