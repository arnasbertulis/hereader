import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';
import 'package:app/reading/paste_reader_screen.dart';

void main() {
  testWidgets('launches into the paste screen with reading disabled',
      (tester) async {
    await tester.pumpWidget(const HereaderApp());

    expect(find.byType(PasteReaderScreen), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Read this'),
    );
    expect(button.onPressed, isNull,
        reason: 'reading should stay disabled until there is text');
  });

  testWidgets('entering text enables reading', (tester) async {
    await tester.pumpWidget(const HereaderApp());

    await tester.enterText(find.byType(TextField), 'Labas rytas.');
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Read this'),
    );
    expect(button.onPressed, isNotNull);
  });
}