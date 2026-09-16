import 'package:app/reading/shelf_layout.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('measuredShelfTextBlockHeight', () {
    const style = TextStyle(fontSize: 16, height: 1.3);
    const lines = [
      ShelfTextLine(
        sampleTexts: [
          'A very long book title that always wraps onto two full lines',
        ],
        style: style,
        maxLines: 2,
        gapBefore: 8,
      ),
      ShelfTextLine(sampleTexts: ['Ag'], style: style, maxLines: 1),
    ];

    test('grows with the platform text scale', () {
      final atOne = measuredShelfTextBlockHeight(
        TextScaler.linear(1),
        200,
        lines,
      );
      final atTwo = measuredShelfTextBlockHeight(
        TextScaler.linear(2),
        200,
        lines,
      );

      expect(atTwo, greaterThan(atOne));
    });

    test('takes the tallest of a line with several candidate strings', () {
      const withCandidates = [
        ShelfTextLine(
          sampleTexts: ['x', 'a much taller candidate string right here'],
          style: style,
        ),
      ];
      const withOnlyTheShortOne = [
        ShelfTextLine(sampleTexts: ['x'], style: style),
      ];

      final tall = measuredShelfTextBlockHeight(
        TextScaler.noScaling,
        80,
        withCandidates,
      );
      final short = measuredShelfTextBlockHeight(
        TextScaler.noScaling,
        80,
        withOnlyTheShortOne,
      );

      // The candidate list's long string wraps onto a second line at this
      // width, which the short-only line never does.
      expect(tall, greaterThan(short));
    });
  });

  group('shelfShouldDropColumn', () {
    Future<bool> dropsAt(
      WidgetTester tester, {
      required double textSize,
      required double platformScale,
    }) async {
      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(brightness: Brightness.light, textScale: textSize),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(platformScale)),
            child: Builder(
              builder: (context) {
                result = shelfShouldDropColumn(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return result;
    }

    testWidgets('does not drop a column at Text size 1.0, platform scale 1.0', (
      tester,
    ) async {
      expect(await dropsAt(tester, textSize: 1.0, platformScale: 1.0), isFalse);
    });

    testWidgets('drops a column at Text size 1.5, platform scale 1.0', (
      tester,
    ) async {
      expect(await dropsAt(tester, textSize: 1.5, platformScale: 1.0), isTrue);
    });

    testWidgets('drops a column at Text size 1.0, platform scale 2.0', (
      tester,
    ) async {
      expect(await dropsAt(tester, textSize: 1.0, platformScale: 2.0), isTrue);
    });
  });
}
