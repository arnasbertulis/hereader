import 'package:flutter/material.dart';

/// One control on a chrome screen: a label, at most one supporting sentence,
/// and whatever the row does when tapped or the glyph it carries.
///
/// Introduced for ADR 0036: the budget is one sentence per control, and a
/// [Widget] slot for that sentence cannot enforce a budget — a caller can
/// always pass a paragraph, or a column of several. Taking [supportingText]
/// as a [String] makes a second sentence a compile-time impossibility rather
/// than a review comment. The line wraps and is never truncated (no
/// `maxLines`, no `overflow`): the budget caps sentences, not rendered
/// lines, and at text scale 2.0 a truncated line would cut the sentence the
/// budget exists to keep — see the widget test in
/// `control_row_budget_test.dart`.
///
/// Anything longer belongs behind an [InfoDot] passed as [trailing], not in
/// [supportingText].
class ControlRow extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? supportingText;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;

  const ControlRow({
    super.key,
    this.icon,
    required this.title,
    this.supportingText,
    this.trailing,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supporting = supportingText;

    return ListTile(
      selected: selected,
      leading: icon == null ? null : Icon(icon),
      title: Text(title),
      subtitle: supporting == null
          ? null
          : Text(
              supporting,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
