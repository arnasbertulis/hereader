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

/// The one line weight surfaces are separated by, in place of elevation or
/// shadow. See section 2 of the UI brief: shadows are also a performance
/// cost, since blur rasterises on the main thread until COOP/COEP and
/// `--wasm` ship.
abstract final class AppHairline {
  static const double width = 1;
  static const double widthHighContrast = 2;
}
