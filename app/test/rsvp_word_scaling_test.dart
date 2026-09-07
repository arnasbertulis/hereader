import 'package:app/reading/profile_presentation.dart';
import 'package:app/reading/rsvp_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

PlaybackUpdate _showing(String word) => PlaybackUpdate(
  state: PlaybackState.paused,
  index: 0,
  token: Token(text: word, charOffset: 0),
);

/// Pumps [RsvpView] inside a box of exactly [width], so the word's
/// LayoutBuilder sees that much room regardless of the test surface's own
/// (fixed, phone-sized) default size.
Future<void> _pumpAtWidth(
  WidgetTester tester, {
  required double width,
  required double fontSizePt,
}) async {
  // The default test surface is 800x600 — too narrow for the wide-viewport
  // cases below, which would otherwise get silently clamped by the window
  // itself rather than by the scaling logic under test.
  tester.view.physicalSize = Size(width + 400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final presentation = resolvePresentation(
    PresentationConfig(fontSizePt: fontSizePt),
    Brightness.light,
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: width,
          height: 600,
          child: RsvpView(
            update: _showing('reading'),
            presentation: presentation,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('the RSVP word font size', () {
    testWidgets('stays at the profile size in a narrow, phone-sized viewport', (
      tester,
    ) async {
      await _pumpAtWidth(tester, width: 300, fontSizePt: 44);

      final word = tester.widget<Text>(find.text('reading'));
      expect(word.style?.fontSize, 44);
    });

    testWidgets(
      'grows past the profile size in a wide, desktop-sized viewport',
      (tester) async {
        await _pumpAtWidth(tester, width: 600, fontSizePt: 44);

        final word = tester.widget<Text>(find.text('reading'));
        expect(word.style?.fontSize, greaterThan(44));
        expect(
          word.style?.fontSize,
          lessThan(PresentationConfig.maxFontSizePt),
        );
      },
    );

    testWidgets('is capped at the profile ceiling on an ultrawide viewport', (
      tester,
    ) async {
      await _pumpAtWidth(tester, width: 2000, fontSizePt: 44);

      final word = tester.widget<Text>(find.text('reading'));
      expect(word.style?.fontSize, PresentationConfig.maxFontSizePt);
    });
  });
}
