import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A header introducing a group of rows on a settings or profiles screen.
///
/// Rendered in [TextTheme.titleLarge] — the Section header role from
/// ADR 0031: its own size (20/w600), distinct from the Row label it heads
/// (16/w600), separated by size and `onSurfaceVariant` colour rather than by
/// colour alone. Four screens each declared their own copy of this widget;
/// one had drifted to `titleSmall` (which fell back to Material's default
/// because `app_typography.dart` never defined that role) and a fifth inline
/// copy added `onSurfaceVariant` dimming on top. Both inverted the intended
/// hierarchy. See issue #346.
class SectionHeader extends StatelessWidget {
  final String title;
  final EdgeInsetsGeometry padding;

  /// An [InfoDot] (or similar) placed after the title — see #357. Optional;
  /// most headers pass none.
  final Widget? info;

  /// The section's one supporting sentence — ADR 0036's budget: a header and
  /// at most one sentence, nothing else printed. Taken as a [String] rather
  /// than a [Widget] for the same reason [ControlRow.supportingText] is: a
  /// second sentence, or a paragraph, is then a compile-time impossibility
  /// rather than a review comment. Wraps, never truncates.
  final String? supportingText;

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
    this.supportingText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Text(title, style: theme.textTheme.titleLarge);
    // Flexible, not mainAxisSize.min alone: a Row still hands its Text an
    // unbounded width to lay out against unless something claims the
    // remaining space, so the title never wraps and overflows once the info
    // affordance and a long title compete for room at text scale 2.0.
    final heading = info == null
        ? text
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(child: text),
              info!,
            ],
          );
    final supporting = supportingText;

    return Semantics(
      header: true,
      child: Padding(
        padding: padding,
        child: supporting == null
            ? heading
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading,
                  Text(
                    supporting,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
