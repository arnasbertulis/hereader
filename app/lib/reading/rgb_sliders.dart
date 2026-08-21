import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'setting_slider.dart';

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
///
/// The one RGB picker in the app, used by the custom accent screen and by
/// the profile editor's background field.
class RgbSliders extends StatelessWidget {
  final int argb;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onSettled;

  const RgbSliders({
    super.key,
    required this.argb,
    required this.onChanged,
    this.onSettled,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final red = redOf(argb);
    final green = greenOf(argb);
    final blue = blueOf(argb);

    return Column(
      children: [
        _channel('Red', red, (v) => argbFrom(v, green, blue)),
        _channel('Green', green, (v) => argbFrom(red, v, blue)),
        _channel('Blue', blue, (v) => argbFrom(red, green, v)),
      ],
    );
  }

  Widget _channel(String label, int value, int Function(int) recombine) =>
      SettingSlider(
        label: label,
        value: value.toDouble(),
        valueLabel: '$value',
        min: 0,
        max: 255,
        // One division per value, so a keyboard or a screen reader moves by
        // one rather than by a fraction that rounds to the same number twice.
        divisions: 255,
        enabled: enabled,
        onChanged: (v) => onChanged(recombine(v.round())),
        onChangeEnd: onSettled == null
            ? null
            : (v) => onSettled!(recombine(v.round())),
      );
}
