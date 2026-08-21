import 'dart:math' as math;

/// WCAG contrast maths and ARGB component access, with no Flutter
/// dependency.
///
/// This lived in the app as part of `profile_presentation.dart` until the UI
/// pass. It touches only `int` and `dart:math`, so keeping it in the app put
/// it on the one platform the CI `dart2js` run cannot reach: `app/test/` is
/// compiled by DDC, whose integer semantics differ from `dart2js` at exactly
/// the width edges this file avoids. Moving it here means the
/// scheme-contrast test that checks every accent against every surface now
/// runs under `dart test -p chrome` as well, which is the rule ADR 0009
/// states for anything whose correctness could depend on the compilation
/// target.

/// Component reads and writes use division and modulo rather than shifts and
/// masks.
///
/// Dart's `int` compiles to a JavaScript double on web, and this project has
/// already lost a day to bit manipulation that was exact on the VM and wrong
/// in a browser (`newProfileId`, see `profile.dart`). Every value here stays
/// below 2^32, so plain arithmetic is exact on both targets and needs no
/// reasoning about operator width.
int _unsigned(int argb) => argb < 0 ? argb + 0x100000000 : argb;

int alphaOf(int argb) => (_unsigned(argb) ~/ 0x1000000) % 0x100;
int redOf(int argb) => (_unsigned(argb) ~/ 0x10000) % 0x100;
int greenOf(int argb) => (_unsigned(argb) ~/ 0x100) % 0x100;
int blueOf(int argb) => _unsigned(argb) % 0x100;

/// Builds an ARGB integer. Opaque unless told otherwise.
///
/// The colour picker always passes a full alpha: a translucent reading
/// background would composite against whatever the platform happens to put
/// behind it, which is not something a reader can predict or configure.
int argbFrom(int red, int green, int blue, {int alpha = 0xFF}) =>
    alpha * 0x1000000 + red * 0x10000 + green * 0x100 + blue;

double _linearised(int component) {
  final c = component / 255.0;
  return c <= 0.03928
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG 2.1 relative luminance.
double relativeLuminance(int argb) =>
    0.2126 * _linearised(redOf(argb)) +
    0.7152 * _linearised(greenOf(argb)) +
    0.0722 * _linearised(blueOf(argb));

/// WCAG 2.1 contrast ratio, from 1.0 (identical) to 21.0 (black on white).
double contrastRatio(int foregroundArgb, int backgroundArgb) {
  final a = relativeLuminance(foregroundArgb);
  final b = relativeLuminance(backgroundArgb);

  final lighter = math.max(a, b);
  final darker = math.min(a, b);

  return (lighter + 0.05) / (darker + 0.05);
}

enum ContrastRating { high, adequate, low, veryLow }

/// Judges a ratio against the thresholds that matter for this app.
///
/// WCAG would call 3.0 a pass for text this size. That bar is set for people
/// who can read a page; it is the wrong bar for the reader this app exists
/// for, so this treats 4.5 as the floor and only calls 7.0 good.
///
/// Nothing in the engine acts on this rating. A reader with light
/// sensitivity may want a lower ratio deliberately, and the app warns
/// rather than blocks. See `fadeWarning` in `profile_presentation.dart` for
/// the same reasoning applied to timing.
ContrastRating rateContrast(double ratio) {
  if (ratio >= 7.0) return ContrastRating.high;
  if (ratio >= 4.5) return ContrastRating.adequate;
  if (ratio >= 3.0) return ContrastRating.low;
  return ContrastRating.veryLow;
}
