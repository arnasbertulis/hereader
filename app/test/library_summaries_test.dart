import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// Records the SQL of every select the database runs.
///
/// The subject here is what a query *reads*, which no assertion on a return
/// value can reach: the summaries were correct before this fix and correct
/// after it, and the only difference was a blob per book per emission.
///
/// Asserting on statement text is brittle in general and exact here, because
/// the select list is the behaviour under test. A rewrite that changes the
/// phrasing without dropping the column should fail this.
class _RecordedSelects extends QueryInterceptor {
  final List<String> statements = [];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return executor.runSelect(statement, args);
  }
}

void main() {
  late _RecordedSelects selects;
  late AppDatabase database;
  late LibraryRepository repo;

  setUp(() {
    selects = _RecordedSelects();
    database = AppDatabase(NativeDatabase.memory().interceptWith(selects));
    repo = LibraryRepository(database);
  });

  tearDown(() => database.close());

  Future<void> addBook(String id, {String title = 'Romeo and Juliet'}) =>
      repo.addBook(
        id: id,
        title: title,
        author: 'William Shakespeare',
        // Large enough that reading it is a real cost rather than a
        // theoretical one, and small enough not to slow the suite.
        bytes: Uint8List(256 * 1024),
        wordCount: 25000,
      );

  group('the library list', () {
    test('does not read book bytes', () async {
      await addBook('book-1');
      await addBook('book-2', title: 'Hamlet');

      // addBook selects on its own way through, since the pending-position
      // drain reads a table of its own. Those are not the subject.
      selects.statements.clear();

      await repo.watchLibrary().first;

      expect(
        selects.statements,
        isNotEmpty,
        reason: 'the query has to have run for the rest to mean anything',
      );
      expect(
        selects.statements.where((sql) => sql.contains('"bytes"')),
        isEmpty,
        reason: 'a list of titles must not load every EPUB in the library',
      );
    });

    test('still carries everything a row draws', () async {
      await addBook('book-1');

      final summary = (await repo.watchLibrary().first).single;

      expect(summary.id, 'book-1');
      expect(summary.title, 'Romeo and Juliet');
      expect(summary.author, 'William Shakespeare');
      expect(summary.wordCount, 25000);
      expect(summary.importedAt, isNotNull);
      expect(summary.position, isNull);
    });

    test('carries a position once the book has been opened', () async {
      await addBook('book-1');

      await repo.savePosition(
        bookId: 'book-1',
        locator: const Locator(
          blockId: 'block-1',
          charOffset: 42,
          parserVersion: 1,
        ),
        hlc: '0000000000001-00000-test',
        tokenIndex: 17,
      );

      final summary = (await repo.watchLibrary().first).single;

      expect(summary.position?.blockId, 'block-1');
      expect(summary.position?.charOffset, 42);
      expect(summary.position?.parserVersion, 1);
    });

    test('emits again when a position is written', () async {
      await addBook('book-1');

      // This is what could plausibly break. Naming the joined table's
      // columns by hand rather than letting the join contribute them means
      // the query still has to mention reading_positions; one that did not
      // would stop being woken by writes to it, and a reader would see a
      // stale place until something else happened to touch books.
      final withPosition = repo.watchLibrary().firstWhere(
        (books) => books.single.position != null,
      );

      await repo.savePosition(
        bookId: 'book-1',
        locator: const Locator(
          blockId: 'block-1',
          charOffset: 42,
          parserVersion: 1,
        ),
        hlc: '0000000000001-00000-test',
      );

      final books = await withPosition.timeout(const Duration(seconds: 5));

      expect(books.single.position?.charOffset, 42);
    });
  });
}
