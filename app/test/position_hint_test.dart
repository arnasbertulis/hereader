import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'test_database.dart';

/// How far into the book a position claims to be, read straight from the
/// table.
///
/// No repository accessor yet. Nothing in the app reads this value, and an
/// accessor written for a test to call is an accessor nobody maintains.
Future<int?> _hint(AppDatabase db, String bookId) async {
  final row = await (db.select(
    db.readingPositions,
  )..where((p) => p.bookId.equals(bookId))).getSingleOrNull();

  return row?.tokenIndex;
}

Locator _at(String blockId) =>
    Locator(blockId: blockId, charOffset: 0, parserVersion: 1);

void main() {
  late AppDatabase db;
  late LibraryRepository repository;

  setUp(() {
    db = AppDatabase(testExecutor());
    repository = LibraryRepository(db);
  });

  tearDown(() => db.close());

  Future<void> addBook(String id) => repository.addBook(
    id: id,
    title: 'Romeo and Juliet',
    author: 'William Shakespeare',
    bytes: Uint8List.fromList([1, 2, 3]),
    wordCount: 25000,
    sourceFormat: 'epub',
  );

  test('a saved position keeps the hint it was given', () async {
    await addBook('book-1');

    await repository.savePosition(
      bookId: 'book-1',
      locator: _at('block-7'),
      hlc: '0000000000001-00000-here',
      tokenIndex: 400,
    );

    expect(await _hint(db, 'book-1'), 400);
  });

  test('a save without a hint clears the one before it', () async {
    await addBook('book-1');

    await repository.savePosition(
      bookId: 'book-1',
      locator: _at('block-7'),
      hlc: '0000000000001-00000-here',
      tokenIndex: 400,
    );

    await repository.savePosition(
      bookId: 'book-1',
      locator: _at('block-9'),
      hlc: '0000000000002-00000-here',
    );

    // The hint describes the position it was written with. Keeping 400 here
    // would pair a count from where the reader used to be with a locator for
    // where they are now, and the service measures divergence with it.
    expect(await _hint(db, 'book-1'), isNull);
  });

  test('a remote position stores the hint that arrived with it', () async {
    await addBook('book-1');

    await repository.applyRemotePosition(
      bookId: 'book-1',
      locator: _at('block-3'),
      hlc: '0000000000005-00000-other',
      tokenIndex: 1200,
    );

    expect(await _hint(db, 'book-1'), 1200);
  });

  test('a position held for an absent book keeps its hint', () async {
    await repository.applyRemotePosition(
      bookId: 'book-2',
      locator: _at('block-3'),
      hlc: '0000000000005-00000-other',
      tokenIndex: 900,
    );

    // Held rather than written: this device has no such book, so the foreign
    // key on reading_positions cannot be satisfied.
    final held = await (db.select(
      db.pendingPositions,
    )..where((p) => p.bookId.equals('book-2'))).getSingle();

    expect(held.tokenIndex, 900);

    // Drained by the import, in the same transaction, so the book never
    // exists without the place that was waiting for it.
    await addBook('book-2');

    expect(await _hint(db, 'book-2'), 900);
  });

  test('a remote position without a hint is applied anyway', () async {
    await addBook('book-1');

    // What a client older than the column sends. A missing hint is a value
    // this device does not know, not an event it cannot apply, and refusing
    // it would count as a skipped event and advance sync.last_seq past it.
    await repository.applyRemotePosition(
      bookId: 'book-1',
      locator: _at('block-4'),
      hlc: '0000000000005-00000-other',
    );

    final row = await (db.select(
      db.readingPositions,
    )..where((p) => p.bookId.equals('book-1'))).getSingle();

    expect(row.blockId, 'block-4');
    expect(row.tokenIndex, isNull);
  });
}
