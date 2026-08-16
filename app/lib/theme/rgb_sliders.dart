import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';
import '../reading/profile_presentation.dart';

import 'app_tokens.dart';

/// A colour as three sliders.
///
/// Sliders rather than a wheel or a gradient square, for the reason the
/// reading-background picker gives: this app is used by people who cannot
/// reliably hit a small target, and three long tracks are easier to work
/// than a two-dimensional field. Alpha is fixed opaque.
///
/// [onChanged] fires while a track is being dragged and [onSettled] once it
/// is released. A caller that persists on every frame of a drag writes a row
/// per pixel, so the appearance screen paints from the first and writes on
/// the second.
class RgbSliders extends StatelessWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  final ValueChanged<Color>? onSettled;

  const RgbSliders({
    super.key,
    required this.color,
    required this.onChanged,
    this.onSettled,
  });

  @override
  Widget build(BuildContext context) {
    final argb = color.toARGB32();
    final red = redOf(argb);
    final green = greenOf(argb);
    final blue = blueOf(argb);

    return Column(
      children: [
        _Channel(
          label: 'Red',
          value: red,
          onChanged: (v) => onChanged(colorOf(argbFrom(v, green, blue))),
          onSettled: onSettled == null
              ? null
              : (v) => onSettled!(colorOf(argbFrom(v, green, blue))),
        ),
        _Channel(
          label: 'Green',
          value: green,
          onChanged: (v) => onChanged(colorOf(argbFrom(red, v, blue))),
          onSettled: onSettled == null
              ? null
              : (v) => onSettled!(colorOf(argbFrom(red, v, blue))),
        ),
        _Channel(
          label: 'Blue',
          value: blue,
          onChanged: (v) => onChanged(colorOf(argbFrom(red, green, v))),
          onSettled: onSettled == null
              ? null
              : (v) => onSettled!(colorOf(argbFrom(red, green, v))),
        ),
      ],
    );
  }
}

class _Channel extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onSettled;

  const _Channel({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onSettled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              Text('$value', style: theme.textTheme.labelLarge),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            // One division per value, so a keyboard or a screen reader moves
            // by one rather than by a fraction that rounds to the same
            // number twice.
            divisions: 255,
            label: '$label $value',
            onChanged: (v) => onChanged(v.round()),
            onChangeEnd: onSettled == null
                ? null
                : (v) => onSettled!(v.round()),
          ),
        ],
      ),
    );
  }
}
