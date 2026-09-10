import 'package:app/reading/control_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ADR 0036: a control is its label plus at most one supporting sentence,
/// taken as a [String] so a second sentence is a compile-time impossibility.
/// The sentence wraps and is never truncated, at any text scale.
void main() {
  Widget pump(Widget child, {double textScale = 1.0}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: child),
    ),
  );

  testWidgets('renders only the title when no supporting text is given', (
    tester,
  ) async {
    await tester.pumpWidget(pump(const ControlRow(title: 'Appearance')));

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('renders the supporting sentence as one Text below the title', (
    tester,
  ) async {
    await tester.pumpWidget(
      pump(
        const ControlRow(title: 'Appearance', supportingText: 'Light · Blue'),
      ),
    );

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Light · Blue'), findsOneWidget);
    expect(find.byType(Text), findsNWidgets(2));
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the supporting sentence never truncates at scale $scale', (
      tester,
    ) async {
      const sentence =
          'A sentence long enough to wrap onto more than one line once '
          'the text scale grows.';

      await tester.pumpWidget(
        pump(
          const ControlRow(title: 'Appearance', supportingText: sentence),
          textScale: scale,
        ),
      );

      final subtitle = tester.widget<Text>(find.text(sentence));

      expect(subtitle.maxLines, isNull);
      expect(subtitle.overflow, isNot(TextOverflow.ellipsis));
    });
  }

  testWidgets('a tap reaches onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      pump(ControlRow(title: 'Appearance', onTap: () => tapped = true)),
    );

    await tester.tap(find.text('Appearance'));

    expect(tapped, isTrue);
  });
}
