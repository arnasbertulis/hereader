import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/book_importer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'test_database.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repository;
  late BuildContext context;

  setUp(() {
    db = AppDatabase(testExecutor());
    repository = LibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// Hands the test a real [BuildContext] under a [MaterialApp] and a
  /// [Scaffold], which is what [BookImporter] reports failures through.
  Future<void> mountContext(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
  }

  testWidgets('a cancelled pick changes nothing and reports nothing', (
    tester,
  ) async {
    await mountContext(tester);

    final importer = BookImporter(
      repository: repository,
      pickBytes: () async => null,
      parser: StubBookParser(fixtureBook(id: 'book-1', title: 'A Book')),
    );

    final outcome = await importer.importPickedFile(context);
    await tester.pump();

    expect(outcome, ImportOutcome.cancelled);
    expect(await repository.hasBook('book-1'), isFalse);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a successful pick lands the Book', (tester) async {
    await mountContext(tester);

    final importer = BookImporter(
      repository: repository,
      pickBytes: () async => Uint8List.fromList([1, 2, 3]),
      parser: StubBookParser(fixtureBook(id: 'book-1', title: 'A Book')),
    );

    final outcome = await importer.importPickedFile(context);

    expect(outcome, ImportOutcome.imported);
    expect(await repository.hasBook('book-1'), isTrue);
  });

  testWidgets('a parse failure reports and leaves the Library empty', (
    tester,
  ) async {
    await mountContext(tester);

    final importer = BookImporter(
      repository: repository,
      pickBytes: () async => Uint8List.fromList([1, 2, 3]),
      parser: const ThrowingBookParser(),
    );

    final outcome = await importer.importPickedFile(context);
    await tester.pump();

    expect(outcome, ImportOutcome.failed);
    expect(find.text('The file could not be read as an EPUB.'), findsOneWidget);

    // A one-shot query rather than `watchLibrary()`: a watch stream's
    // cancellation schedules a Drift timer that only fires on a pumped
    // frame, and nothing later in this test drives one.
    expect(await db.select(db.books).get(), isEmpty);
  });

  testWidgets('importBytes lands a Book without touching the picker', (
    tester,
  ) async {
    await mountContext(tester);

    final importer = BookImporter(
      repository: repository,
      pickBytes: () => throw StateError('picker should not be called'),
      parser: StubBookParser(fixtureBook(id: 'book-1', title: 'A Book')),
    );

    final outcome = await importer.importBytes(
      context,
      Uint8List.fromList([1, 2, 3]),
    );

    expect(outcome, ImportOutcome.imported);
    expect(await repository.hasBook('book-1'), isTrue);
  });

  test('cancelled and failed are distinct outcomes', () {
    expect(ImportOutcome.cancelled, isNot(ImportOutcome.failed));
  });
}
