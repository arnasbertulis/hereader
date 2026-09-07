import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A header introducing a group of rows on a settings or profiles screen.
///
/// Rendered in [TextTheme.titleMedium] — larger and heavier than the rows it
/// heads, never smaller or dimmer. Four screens each declared their own copy
/// of this widget; one had drifted to `titleSmall` (which falls back to
/// Material's default because `app_typography.dart` never defines that role)
/// and a fifth inline copy added `onSurfaceVariant` dimming on top. Both
/// inverted the intended hierarchy. See issue #346.
class SectionHeader extends StatelessWidget {
  final String title;
  final EdgeInsetsGeometry padding;

  /// An [InfoDot] (or similar) placed after the title — see #357. Optional;
  /// most headers pass none.
  final Widget? info;

  const SectionHeader(
    this.title, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.xl,
      AppSpacing.lg,
      AppSpacing.sm,
    ),
    this.info,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(title, style: Theme.of(context).textTheme.titleMedium);

    return Semantics(
      header: true,
      child: Padding(
        padding: padding,
        child: info == null
            ? text
            : Row(mainAxisSize: MainAxisSize.min, children: [text, info!]),
      ),
    );
  }
}
