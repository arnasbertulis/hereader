/// Caps a screen body at a comfortable reading/interaction width and centres
/// it, so a screen laid out for a phone does not stretch edge to edge on a
/// wide desktop window.
///
/// `home_screen.dart` proved the pattern first, locally. This is the same
/// `Center` + `ConstrainedBox` pair, shared so every screen that needs it
/// reaches for one widget instead of re-deriving it.
library;

import 'package:flutter/widgets.dart';

import 'app_tokens.dart';

/// Wraps [child] in a [Center] + [ConstrainedBox] pair capped at [maxWidth].
///
/// Defaults to [AppContent.maxWidth] — the width for settings lists and
/// forms. Prose passes [AppContent.proseMaxWidth] instead.
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = AppContent.maxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
