import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_tokens.dart';

/// Key for the dialog-path "Close" button, so a test can drive it without
/// asserting on its label — see `.claude/rules/app.md`.
const Key infoDotCloseButtonKey = Key('info-dot-close-button');

/// The (i) that moves a setting's second and third sentences off the page.
///
/// Every explanation used to print unconditionally, at [bodySmall], whether
/// or not the reader wanted it. [InfoDot] is the mechanism that lets a
/// screen keep one line of plain text under a label and put the rest behind
/// a tap — see #357. It is placed after the label, never inside a
/// [ListTile]'s own `title`, and budgeted: one only where a setting is
/// genuinely non-obvious, not on every row.
///
/// Below [_wideBreakpoint] the explanation opens in a bottom sheet; at or
/// above it, a dialog. 600 is the same wide/narrow line `home_screen.dart`
/// and `library_screen.dart` already use.
///
/// [semanticLabel] must name what the explanation is about — `'About high
/// contrast'`, never `'info'` or `'button'` — or a screen reader announces
/// the same word at every row on the page.
///
/// [explanation] is plain text. A caller whose disclosure is not prose —
/// the reader transport legend's list of controls, ADR 0037 §2 — passes
/// [contentBuilder] instead; exactly one of the two is required.
class InfoDot extends StatelessWidget {
  final String semanticLabel;
  final String? explanation;
  final WidgetBuilder? contentBuilder;

  const InfoDot({
    super.key,
    required this.semanticLabel,
    this.explanation,
    this.contentBuilder,
  }) : assert(
         explanation != null || contentBuilder != null,
         'InfoDot needs either explanation or contentBuilder',
       );

  static const _wideBreakpoint = 600.0;

  Widget _content(BuildContext context, TextTheme textTheme) {
    final builder = contentBuilder;
    if (builder != null) return builder(context);
    return Text(explanation!, style: textTheme.bodyLarge);
  }

  @override
  Widget build(BuildContext context) {
    // A trailing IconButton rather than a glyph inside the row's own title:
    // an IconButton's default hit area is already 48x48 even though the
    // glyph it draws is ~20px, and it owns its own tap rather than sharing
    // the row's.
    return Semantics(
      button: true,
      label: semanticLabel,
      // One node for the button, not the button's own (unlabelled) node
      // plus a stray label beside it — the accent swatch does the same.
      excludeSemantics: true,
      child: IconButton(
        icon: const Icon(AppIcons.infoDisclosure, size: 20),
        onPressed: () => _open(context),
      ),
    );
  }

  void _open(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    if (wide) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(semanticLabel),
          content: _content(dialogContext, theme.textTheme),
          actions: [
            TextButton(
              key: infoDotCloseButtonKey,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }

    // `showModalBottomSheet` reads its container's colour, elevation and
    // shape off `Theme.of(context)` at this call site rather than off the
    // builder — see `.claude/rules/app.md`'s trap. Read here and wrapped
    // below, so a caller sitting under a locally overridden Theme (the
    // reader's own chrome, say) still gets a sheet that matches its
    // contents rather than the app root's.
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.bottomSheetTheme.backgroundColor,
      elevation: theme.bottomSheetTheme.elevation,
      shape: theme.bottomSheetTheme.shape,
      builder: (sheetContext) => Theme(
        data: theme,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: _content(sheetContext, theme.textTheme),
          ),
        ),
      ),
    );
  }
}
