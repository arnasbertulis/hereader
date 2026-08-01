import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

import 'package:app/main.dart';
import 'package:app/reading/library_screen.dart';
import 'package:app/reading/paste_reader_screen.dart';
import 'package:drift/native.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/data/database.dart';

void main() {
  testWidgets('launches into an empty library', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(HereaderApp(repository: LibraryRepository(db)));

    expect(find.byType(LibraryScreen), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('No books yet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
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

  testWidgets('shows a book that is already stored', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final repo = LibraryRepository(db);
    await repo.addBook(
      id: 'test-1',
      title: 'Romeo and Juliet',
      author: 'William Shakespeare',
      bytes: Uint8List.fromList([1, 2, 3]),
      wordCount: 25000,
    );

    await tester.pumpWidget(HereaderApp(repository: repo));
    await tester.pumpAndSettle();

    expect(find.text('Romeo and Juliet'), findsOneWidget);
    expect(find.text('William Shakespeare'), findsOneWidget);
    expect(find.text('25000 words'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
