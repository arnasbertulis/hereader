import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_tokens.dart';
import '../theme/appearance.dart';
import 'profile_presentation.dart';
import 'rgb_sliders.dart';

/// An accent outside the six named ones.
///
/// The stored format needed nothing for this: `encodeAccent` has always
/// written six hex digits rather than an accent's name, so an arbitrary
/// colour was already representable and no migration is involved.
///
/// The colour is applied on release rather than on every frame of a drag.
/// Each write is a preference row and a clock stamp, and a drag across a
/// track would issue a few hundred of them.
class CustomAccentScreen extends StatefulWidget {
  final AppearanceController controller;

  const CustomAccentScreen({super.key, required this.controller});

  @override
  State<CustomAccentScreen> createState() => _CustomAccentScreenState();
}

class _CustomAccentScreenState extends State<CustomAccentScreen> {
  late Color _color = widget.controller.settings.accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Custom accent')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.outline,
                      width: AppHairline.width,
                    ),
                  ),
                  child: Icon(AppIcons.confirm, color: onAccent(_color)),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    hexOf(_color.toARGB32()),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          RgbSliders(
            argb: _color.toARGB32(),
            // The swatch above follows the drag; the app follows the
            // release. Both are visible at once, so a reader dragging can
            // see where they are going before the whole screen goes there.
            onChanged: (argb) => setState(() => _color = colorOf(argb)),
            onSettled: (argb) => widget.controller.setAccent(colorOf(argb)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              'The colour you pick is a starting point rather than the exact '
              'ink on a button. The app derives a readable set of shades '
              'from it, so a very pale or very dark choice still leaves text '
              'legible on top of it.\n\n'
              'The accent reaches buttons, selected rows, progress and focus '
              'rings. It never reaches the reading surface, whose colours '
              'belong to the reading profile you chose.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
