@TestOn('vm')
library;

import 'dart:io';

import 'package:app/theme/app_colors.dart';
import 'package:app/theme/appearance.dart';
import 'package:app/theme/theme_mirror_key.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// The web page paints its own background before Flutter has painted
/// anything, so the two surface colours are written down twice: once in
/// `app_colors.dart` and once in `web/index.html`. HTML cannot read a Dart
/// constant and there is no build step here that could inject one, so the
/// duplication is unavoidable and this test is what stops it drifting.
///
/// The project has already lost a colour this way. `RsvpView` carried its
/// own ink and surface constants that fell out of step with the ones the
/// contrast readout measured, so settings judged a pair the app never
/// painted.

String _hex(Color color) {
  final argb = color.toARGB32();
  String pair(int component) =>
      component.toRadixString(16).padLeft(2, '0').toUpperCase();

  return '#${pair(redOf(argb))}${pair(greenOf(argb))}${pair(blueOf(argb))}';
}

Color _surface(Brightness brightness) => buildScheme(
  accent: AppAccents.defaultAccent.color,
  brightness: brightness,
  highContrast: false,
).surface;

void main() {
  test('the loader background matches the surface token', () {
    // `flutter test` runs from the package root.
    final file = File('web/index.html');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'expected web/index.html relative to app/',
    );

    final markup = file.readAsStringSync();

    expect(
      markup,
      contains('background-color: ${_hex(_surface(Brightness.light))}'),
    );
    expect(
      markup,
      contains('background-color: ${_hex(_surface(Brightness.dark))}'),
    );

    // Without this the browser draws form controls and scrollbars light on
    // a dark page, which is visible around the loader.
    expect(markup, contains('name="color-scheme"'));
    expect(markup, contains('prefers-color-scheme: dark'));
  });

  // The reader's own choice beats the browser's preference. The page reads it
  // from a `localStorage` key the app mirrors on every change, so the key is
  // written down in two places and this is what stops them drifting.
  group('the reader\'s chosen theme', () {
    late String markup;

    setUp(() => markup = File('web/index.html').readAsStringSync());

    test('is read from the key the app writes', () {
      expect(
        markup,
        contains("localStorage.getItem('$themeMirrorStorageKey')"),
      );
    });

    test('the script compares against what the app encodes', () {
      expect(
        markup,
        contains(
          "theme === '${encodeThemeMode(ThemeMode.light)}' || "
          "theme === '${encodeThemeMode(ThemeMode.dark)}'",
        ),
      );
    });

    for (final (choice, brightness) in [
      ('light', Brightness.light),
      ('dark', Brightness.dark),
    ]) {
      test(
        '$choice paints the $choice surface whatever the browser prefers',
        () {
          // A rule keyed on the attribute alone, outside the media query, so it
          // applies under either browser preference.
          final rule = RegExp(
            'html\\[data-theme="$choice"\\][^{}]*\\{[^}]*'
            'background-color: ${_hex(_surface(brightness))}',
          );

          expect(rule.hasMatch(markup), isTrue);
        },
      );
    }
  });
}
