import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'test_database.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

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

    expect(await repository.coverOf('book-1'), [0xFF, 0xD8, 0xFF]);
  });

  test('a book without a cover gets no row', () async {
    await addBook('book-1');

    expect(await repository.coverOf('book-1'), isNull);
    expect(await db.select(db.bookCovers).get(), isEmpty);
  });

  test('re-importing without a cover drops the one already there', () async {
    await addBook('book-1', cover: _bytes([0xFF, 0xD8, 0xFF]));

    // The same edition re-imported from a file that declares no cover. The
    // old picture belongs to the copy that is being replaced.
    await addBook('book-1');

    expect(await repository.coverOf('book-1'), isNull);
  });

  test('re-importing with a different cover replaces it', () async {
    await addBook('book-1', cover: _bytes([1]));
    await addBook('book-1', cover: _bytes([2]));

    expect(await repository.coverOf('book-1'), [2]);
  });

  test('removing a book removes its cover', () async {
    await addBook('book-1', cover: _bytes([0xFF, 0xD8, 0xFF]));

    await repository.removeBook('book-1');

    // By cascade, which only fires because beforeOpen turns foreign keys on.
    // Without that pragma this row would outlive the book and be handed to
    // whatever imported the same id next.
    expect(await db.select(db.bookCovers).get(), isEmpty);
  });

  test('reading the same cover twice hits storage once', () async {
    await addBook('book-1', cover: _bytes([0xFF, 0xD8, 0xFF]));

    // The second call is handed the very future the first one started,
    // rather than a new one that would run a second query.
    final first = repository.coverOf('book-1');
    final second = repository.coverOf('book-1');

    expect(identical(first, second), isTrue);
    expect(await second, [0xFF, 0xD8, 0xFF]);
  });

  test(
    'a book already read once gets its new cover on the next read',
    () async {
      await addBook('book-1', cover: _bytes([1]));
      await repository.coverOf('book-1');

      await addBook('book-1', cover: _bytes([2]));

      expect(await repository.coverOf('book-1'), [2]);
    },
  );

  test('removing a book drops its cached cover, not just its row', () async {
    await addBook('book-1', cover: _bytes([1]));
    await repository.coverOf('book-1');

    await repository.removeBook('book-1');

    expect(await repository.coverOf('book-1'), isNull);
  });

  test('changing one book leaves another book\'s cached cover alone', () async {
    await addBook('book-1', cover: _bytes([1]));
    await addBook('book-2', cover: _bytes([2]));

    final bookOneCover = repository.coverOf('book-1');
    await bookOneCover;

    await addBook('book-2', cover: _bytes([9]));

    expect(identical(repository.coverOf('book-1'), bookOneCover), isTrue);
    expect(await repository.coverOf('book-2'), [9]);
  });
}
