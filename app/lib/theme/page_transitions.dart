import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// A route transition that fades and scales rather than slides.
///
/// The platform default slides a full screen across the width of the device
/// over 300ms. Judder is a position error integrated over time, so a long,
/// slow translation of a large area is the worst case a Flutter web build
/// can draw: every frame of it is rendered on the main thread through
/// `requestAnimationFrame`, which Chromium caps at 60Hz on high refresh rate
/// Android panels while the panel itself is still running at 120.
///
/// Opacity and a two percent scale over [AppMotion.state] cost the same
/// number of frames and carry almost no position error, so a dropped frame
/// reads as a slightly abrupt arrival rather than as stutter.
///
/// The same builder covers every platform. A Flutter web build reports the
/// platform it is running on, so leaving Android to the Material default
/// would leave the slide in place on the one target this exists for.
class QuietPageTransitionsBuilder extends PageTransitionsBuilder {
  const QuietPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.state;

  @override
  Duration get reverseTransitionDuration => AppMotion.state;

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // The platform switch, honoured rather than shortened. A reader who
    // asked for no animation gets the arriving screen drawn once, which is
    // what the tab stack already does.
    if (MediaQuery.disableAnimationsOf(context)) return child;

    // Driven off the animation rather than wrapped in a `CurvedAnimation`.
    // A curved animation constructed here would be built again on every
    // rebuild during the transition and never disposed.
    return FadeTransition(
      opacity: animation.drive(CurveTween(curve: _curve)),
      child: ScaleTransition(
        // Up on the way in, and the same two percent back down on the way
        // out, because the animation runs in reverse for a pop.
        scale: animation.drive(
          Tween<double>(begin: 0.98, end: 1).chain(CurveTween(curve: _curve)),
        ),
        child: child,
      ),
    );
  }

  static const _curve = Curves.easeOutCubic;
}

/// [QuietPageTransitionsBuilder] on every platform.
///
/// A `final` rather than a `const`: a collection-for over
/// [TargetPlatform.values] is not a constant expression, and writing the six
/// entries out by hand would be a list to remember the day the enum gains a
/// seventh.
final PageTransitionsTheme quietPageTransitions = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    for (final platform in TargetPlatform.values)
      platform: const QuietPageTransitionsBuilder(),
  },
);
