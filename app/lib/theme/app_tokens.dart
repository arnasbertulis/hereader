/// Spacing, shape and motion values for app chrome.
///
/// No literal colour, radius or duration belongs anywhere else in
/// `app/lib/`. A number repeated at each call site is a number that drifts
/// the next time someone changes one of them and misses the others; a
/// constant here is a number that cannot.
library;

/// 4dp-based spacing scale. Screen padding is 16 below 600dp and 24 from
/// 600dp up, applied at the screen level rather than tokenised here, since
/// it depends on `MediaQuery` rather than being a fixed value.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Three radii, and no others. Chips and progress-bar ends use [sm]; cards,
/// tiles, buttons and rows use [md]; the nav indicator and any FAB use
/// [stadium] via a `StadiumBorder` rather than a numeric radius.
abstract final class AppRadii {
  static const double sm = 4;
  static const double md = 12;
  static const double stadium = 9999;
}

/// Motion durations and the curve every chrome animation shares.
///
/// Nothing above [route], following the performance rule in ADR-pending
/// section 10 of the UI brief: judder from Chrome's main-frame throttle is
/// worst on long, slow translation, so chrome motion stays short rather than
/// trying to out-animate a browser policy nothing here can change. Tab
/// changes cross-fade with no translation at all.
abstract final class AppMotion {
  static const Duration state = Duration(milliseconds: 120);
  static const Duration route = Duration(milliseconds: 180);
}

/// Navigation sizing.
///
/// The breakpoint is where a bar along the bottom stops being the right
/// shape: at 640dp a rail costs horizontal room the layout has and buys back
/// the vertical room a bar takes from a list. [barHeight] is shorter than
/// Material's 80dp default and is a base rather than a fixed height, since
/// nothing here caps the reader's text size.
abstract final class AppNav {
  static const double railBreakpoint = 640;
  static const double barHeight = 64;
}

/// The one line weight surfaces are separated by, in place of elevation.
/// See section 2 of the UI brief. [AppShadow] and [AppFloatShadow] are the
/// two exceptions and each says why.
abstract final class AppHairline {
  static const double width = 1;
  static const double widthHighContrast = 2;
}

/// The shadow under Home's continue tile.
///
/// This said "the one shadow in the app" until the library's add button
/// arrived and made that two. The rule it is an exception to has not moved:
/// surfaces separate with a hairline, and a shadow appears only where a
/// hairline cannot do the job. Both places where it cannot are objects with
/// nothing to draw a line against, and [AppFloatShadow] gives the second one.
///
/// This tile is the only element in the app that sits alone in open space
/// with nothing to align to, and a line under an object that is not against
/// anything does not seat it.
///
/// The cost is real but small: a `BoxShadow` on a rounded rectangle takes
/// Skia's blurred-shape path rather than rasterising a layer, which is what
/// makes `BackdropFilter` the thing worth avoiding on this target. Two
/// shadows, on two widgets, on two screens.
///
/// Two opacities rather than one colour. A shadow is a hole in the light,
/// and a dark surface has less light to take away, so the same alpha that
/// reads as a soft edge on a light background is invisible on a dark one.
///
/// Two layers rather than one, and both offset down far enough to clear the
/// tile's top edge. Light in this app comes from above, so the top of an
/// object catches it and casts nothing, the sides catch the blur alone, and
/// the bottom takes the offset and the blur together. A shadow drawn evenly
/// around all four edges is a glow, and it reads as one.
///
/// The ambient layer is wide and soft and does the seating. The contact
/// layer is tight and sits just under the bottom edge, which is what makes
/// an object look like it is resting on something rather than hovering over
/// it.
abstract final class AppShadow {
  static const double ambientBlur = 40;
  static const double ambientSpread = -8;
  static const double ambientDy = 18;

  static const double contactBlur = 14;
  static const double contactSpread = -4;
  static const double contactDy = 8;

  static const double ambientOpacityLight = 0.26;
  static const double ambientOpacityDark = 0.72;

  static const double contactOpacityLight = 0.20;
  static const double contactOpacityDark = 0.55;
}

/// The shadow under the library's add button.
///
/// The second exception to hairlines, on the same reasoning as [AppShadow]
/// and for a different reason. That tile sits still in open space; this
/// button sits over a shelf that scrolls under it, so what it needs a shadow
/// for is separation from a cover it cannot predict. A hairline ring would
/// draw one weight against every cover in the library, and a dark cover
/// passing under a dark accent leaves a filled circle with nothing to say
/// where it ends.
///
/// Its own numbers rather than [AppShadow]'s. Forty of blur at eighteen down
/// belongs to an object 300dp wide; under a 56dp circle it is a puddle
/// wider than the button. These are the same two layers at roughly a third
/// the distance, so the pair still reads as ambient plus contact.
///
/// Lighter alphas too. The tile carries a shadow to sit in empty space; this
/// one carries it to stay legible over an image, and a heavy shadow on a
/// small bright circle reads as a smudge.
abstract final class AppFloatShadow {
  static const double ambientBlur = 16;
  static const double ambientSpread = -2;
  static const double ambientDy = 6;

  static const double contactBlur = 6;
  static const double contactSpread = -1;
  static const double contactDy = 2;

  static const double ambientOpacityLight = 0.22;
  static const double ambientOpacityDark = 0.60;

  static const double contactOpacityLight = 0.16;
  static const double contactOpacityDark = 0.45;
}
