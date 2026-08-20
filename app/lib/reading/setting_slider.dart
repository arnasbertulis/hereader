import 'package:flutter/material.dart';

import '../theme/app_icons.dart';

/// A labelled slider with its current value spelled out beside it.
///
/// Shared because two settings screens ask the reader for the same kind of
/// number. `profile_edit_screen.dart` defined this privately and Settings ›
/// Reading needed one that looked identical — the step and the rewind are
/// both "how many words", and a control that differed between the two pages
/// would be saying they are different kinds of thing.
///
/// [value] is a double even where the setting is a whole number, because
/// that is what [Slider] takes; callers round on the way out.
class SettingSlider extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final bool enabled;
  final String? help;

  /// Shown below [help], in the error colour. For a value that is legal and
  /// saveable but produces something the reader probably did not intend.
  final String? warning;
  final ValueChanged<double> onChanged;

  const SettingSlider({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.enabled = true,
    this.help,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.disabledColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: enabled ? null : TextStyle(color: dim)),
              Text(
                valueLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: enabled ? null : dim,
                ),
              ),
            ],
          ),
          Slider(
            // Clamped because a profile written by another build may sit
            // outside the range this one offers, and Slider throws rather
            // than pinning.
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: enabled ? onChanged : null,
          ),
          if (help != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(help!, style: theme.textTheme.bodySmall),
            ),
          if (warning != null) SettingWarning(warning!),
        ],
      ),
    );
  }
}

/// One warning line under a setting, in the error colour.
///
/// Lifted out of [SettingSlider] when a control that is not a slider needed
/// the same line: the presentation mode is a segmented button, and a reader
/// should not be able to tell from the styling which kind of control the
/// warning came from.
class SettingWarning extends StatelessWidget {
  final String text;

  const SettingWarning(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.settingWarns, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
