import 'package:rsvp_engine/rsvp_engine.dart';
import 'package:test/test.dart';

/// The WCAG maths and the ARGB component access, on both targets.
///
/// This is the half of the contrast work that ADR 0009 says has to run in a
/// browser: it is arithmetic on integers, and this project has twice shipped
/// integer arithmetic that was exact on the VM and wrong under `dart2js`.
/// `contrast.dart` avoids shifts and masks for exactly that reason, and the
/// values below are what proves it, since the whole suite runs under
/// `dart test -p chrome` as well.
///
/// The app's own contrast test builds `ColorScheme`s and needs Flutter, so it
/// stays in `app/test`, where a browser run means DDC. This file is the half
/// proven under `dart2js`, which is the target the arithmetic could break on.

void main() {
  const white = 0xFFFFFFFF;
  const black = 0xFF000000;
  const ink = 0xFF2F4858;

  group('components', () {
    test('reads each channel', () {
      expect(alphaOf(ink), 0xFF);
      expect(redOf(ink), 0x2F);
      expect(greenOf(ink), 0x48);
      expect(blueOf(ink), 0x58);
    });

    test('round-trips through argbFrom', () {
      expect(argbFrom(0x2F, 0x48, 0x58), ink);
      expect(argbFrom(255, 255, 255), white);
      expect(argbFrom(0, 0, 0), black);
    });

    // The largest value this code handles is 0xFFFFFFFF, which is 2^32 - 1.
    // A JavaScript double represents every integer up to 2^53 exactly, so
    // the arithmetic in `contrast.dart` is exact on both targets — but only
    // because it divides and takes remainders rather than shifting, since
    // `<<` is 32-bit in JavaScript.
    test('handles the top of the range', () {
      expect(white, 4294967295);
      expect(redOf(white), 255);
      expect(greenOf(white), 255);
      expect(blueOf(white), 255);
    });

    // A colour that arrived as a signed 32-bit value reads the same.
    test('reads a negative representation of the same colour', () {
      const signed = ink - 0x100000000;

      expect(signed, lessThan(0));
      expect(redOf(signed), 0x2F);
      expect(greenOf(signed), 0x48);
      expect(blueOf(signed), 0x58);
    });

    test('takes an explicit alpha', () {
      expect(alphaOf(argbFrom(0, 0, 0, alpha: 0x80)), 0x80);
    });
  });

  group('luminance', () {
    test('runs from black to white', () {
      expect(relativeLuminance(black), 0);
      expect(relativeLuminance(white), closeTo(1, 0.0001));
    });

    // The threshold `chromeBrightnessFor` uses to decide whether controls
    // drawn on a reading surface should be light or dark: the point where a
    // colour's contrast against black equals its contrast against white.
    test('0.179 is where black and white are equally legible', () {
      const midpoint = 0.179;
      final againstBlack = (midpoint + 0.05) / 0.05;
      final againstWhite = 1.05 / (midpoint + 0.05);

      expect(againstBlack, closeTo(againstWhite, 0.01));
    });
  });

  group('contrast ratio', () {
    test('black on white is 21 to 1', () {
      expect(contrastRatio(black, white), closeTo(21, 0.0001));
    });

    test('a colour on itself is 1 to 1', () {
      expect(contrastRatio(ink, ink), closeTo(1, 0.0001));
    });

    test('does not care which way round the pair is given', () {
      expect(
        contrastRatio(ink, white),
        closeTo(contrastRatio(white, ink), 1e-9),
      );
    });

    test('ignores alpha, since a reading background is always opaque', () {
      expect(
        contrastRatio(argbFrom(0x2F, 0x48, 0x58, alpha: 0x10), white),
        closeTo(contrastRatio(ink, white), 1e-9),
      );
    });
  });

  group('rating', () {
    // 4.5 rather than WCAG's 3.0 for large text, and 7.0 before this calls
    // anything good. The lower bar is set for people who can read a page.
    test('names the bands at their boundaries', () {
      expect(rateContrast(21), ContrastRating.high);
      expect(rateContrast(7), ContrastRating.high);
      expect(rateContrast(6.99), ContrastRating.adequate);
      expect(rateContrast(4.5), ContrastRating.adequate);
      expect(rateContrast(4.49), ContrastRating.low);
      expect(rateContrast(3), ContrastRating.low);
      expect(rateContrast(2.99), ContrastRating.veryLow);
      expect(rateContrast(1), ContrastRating.veryLow);
    });
  });
}
