import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/reader_screen.dart';
import 'package:epub_reader/epub_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'test_database.dart';

Future<String> _stamp() async => '0000000000001-00000-test';

/// Front matter, then the text. The book opens on the second block.
TokenizedText _text() => TokenizedText.from(const [
  (id: 'front', text: 'Licence notice here.'),
  (id: 'one', text: 'Alpha beta gamma.'),
], parserVersion: 1);

void main() {
  late AppDatabase database;
  late TokenizedText text;

  setUp(() {
    database = AppDatabase(testExecutor());
    text = _text();
  });

  tearDown(() => database.close());

  LibraryBook book({required ContentStartReason reason, Locator? position}) =>
      LibraryBook(
        id: 'b',
        title: 'A Book',
        text: text,
        position: position,
        contentStartIndex: text.startOfBlock('one')!,
        contentStartReason: reason,
      );

  Widget reader(LibraryBook b) => MaterialApp(
    home: ReaderScreen(
      book: b,
      repository: LibraryRepository(database),
      issueStamp: _stamp,
      onSave: (_) async {},
    ),
  );

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('a guessed opening says so and offers the start', (tester) async {
    await tester.pumpWidget(
      reader(book(reason: ContentStartReason.boilerplateHeuristic)),
    );
    await tester.pumpAndSettle();

    // Opened on the text, not on the licence page.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Start at the beginning'), findsOneWidget);

    await tester.tap(find.text('Start at the beginning'));
    await tester.pumpAndSettle();

    // The very start of the file, not a step back from the guess: the app
    // does not know where the text begins, so a second guess about how far
    // to rewind would compound the first.
    expect(find.text('Licence'), findsOneWidget);

    // Answered, so it goes.
    expect(find.text('Start at the beginning'), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('a marker the book supplied needs no comment', (tester) async {
    await tester.pumpWidget(
      reader(book(reason: ContentStartReason.explicitMarker)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Start at the beginning'), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('a reader resuming is not asked again', (tester) async {
    await tester.pumpWidget(
      reader(
        book(
          reason: ContentStartReason.boilerplateHeuristic,
          position: text.locatorAt(text.startOfBlock('one')!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The decision was made, or lived with, in an earlier sitting.
    expect(find.text('Start at the beginning'), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('dismissing it leaves the reader where they were', (
    tester,
  ) async {
    await tester.pumpWidget(
      reader(book(reason: ContentStartReason.boilerplateHeuristic)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Carry on here'));
    await tester.pumpAndSettle();

    expect(find.text('Start at the beginning'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);

    await disposeTree(tester);
  });
}
