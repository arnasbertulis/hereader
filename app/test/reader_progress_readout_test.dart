import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'test_database.dart';

Future<String> _stamp() async => '0000000000001-00000-test';

/// Three blocks, so there is a real fraction of the book behind the reader
/// once it is opened partway in. Every word is distinct, matching the shape
/// `reader_tap_zones_test.dart` uses for the same reason.
TokenizedText _text() => TokenizedText.from(const [
  (id: 'one', text: 'Alpha beta gamma.'),
  (id: 'two', text: 'Delta epsilon zeta.'),
  (id: 'three', text: 'Eta theta iota.'),
], parserVersion: 1);

void main() {
  late AppDatabase database;
  late LibraryRepository repository;

  setUp(() {
    database = AppDatabase(testExecutor());
    repository = LibraryRepository(database);
  });

  tearDown(() => database.close());

  Widget reader() => MaterialApp(
    home: ReaderScreen(
      book: LibraryBook(
        id: 'b',
        title: 'A Book',
        text: _text(),
        position: null,
      ),
      repository: repository,
      issueStamp: _stamp,
      onSave: (_) async {},
    ),
  );

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('shows the book title on the reading surface', (tester) async {
    await tester.pumpWidget(reader());
    await tester.pumpAndSettle();

    // The chapter drawer already carries the title; this asserts it is also
    // on the reading surface itself, not only behind the drawer's edge swipe.
    expect(find.text('A Book'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('shows a visible percentage beside the progress bar', (
    tester,
  ) async {
    await tester.pumpWidget(reader());
    await tester.pumpAndSettle();

    // The bar already carries a `semanticsValue` with the percentage; this
    // asserts a sighted reader gets the same fact, not only a screen reader.
    expect(find.textContaining('%'), findsOneWidget);

    await disposeTree(tester);
  });
}
