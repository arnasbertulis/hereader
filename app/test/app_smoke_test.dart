import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';
import 'package:app/reading/library_screen.dart';
import 'package:app/reading/paste_reader_screen.dart';

void main() {
  testWidgets('launches into an empty library', (tester) async {
    await tester.pumpWidget(const HereaderApp());

    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.text('No books yet'), findsOneWidget);
  });

  testWidgets('the paste screen enables reading once there is text', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PasteReaderScreen()));

    var button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Read this'),
    );
    expect(button.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Labas rytas.');
    await tester.pump();

    button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Read this'),
    );
    expect(button.onPressed, isNotNull);
  });
}
