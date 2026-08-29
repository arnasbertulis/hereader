import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'test_database.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

/// The stored cover for a book, or null when it has none.
///
/// Read straight from the table. Nothing in the app reads covers yet, and an
/// accessor that exists for a test to call is an accessor nobody maintains.
Future<Uint8List?> _cover(AppDatabase db, String bookId) async {
  final row = await (db.select(
    db.bookCovers,
  )..where((c) => c.bookId.equals(bookId))).getSingleOrNull();

  return row?.bytes;
}

void main() {
  late AppDatabase db;
  late LibraryRepository repository;

  setUp(() {
    db = AppDatabase(testExecutor());
    repository = LibraryRepository(db);
  });

  tearDown(() => db.close());

  Future<void> addBook(String id, {Uint8List? cover}) => repository.addBook(
    fixtureBook(
      id: id,
      title: 'Romeo and Juliet',
      author: 'William Shakespeare',
      wordCount: 25000,
      coverBytes: cover,
    ),
    _bytes([1, 2, 3]),
  );

  test('an imported cover is stored beside its book', () async {
    await addBook('book-1', cover: _bytes([0xFF, 0xD8, 0xFF]));

    expect(await _cover(db, 'book-1'), [0xFF, 0xD8, 0xFF]);
  });

  test('a book without a cover gets no row', () async {
    await addBook('book-1');

    expect(await _cover(db, 'book-1'), isNull);
    expect(await db.select(db.bookCovers).get(), isEmpty);
  });

  test('re-importing without a cover drops the one already there', () async {
    await addBook('book-1', cover: _bytes([0xFF, 0xD8, 0xFF]));

    // The same edition re-imported from a file that declares no cover. The
    // old picture belongs to the copy that is being replaced.
    await addBook('book-1');

    expect(await _cover(db, 'book-1'), isNull);
  });

  test('re-importing with a different cover replaces it', () async {
    await addBook('book-1', cover: _bytes([1]));
    await addBook('book-1', cover: _bytes([2]));

    expect(await _cover(db, 'book-1'), [2]);
  });

  test('removing a book removes its cover', () async {
    await addBook('book-1', cover: _bytes([0xFF, 0xD8, 0xFF]));

    await repository.removeBook('book-1');

    // By cascade, which only fires because beforeOpen turns foreign keys on.
    // Without that pragma this row would outlive the book and be handed to
    // whatever imported the same id next.
    expect(await db.select(db.bookCovers).get(), isEmpty);
  });
}
