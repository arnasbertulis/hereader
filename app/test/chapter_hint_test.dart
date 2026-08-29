import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'fakes.dart';
import 'test_database.dart';

/// The chapter a stored position claims to be in, read straight from the
/// table.
///
/// `watchLibrary` carries both of these onto `BookSummary`, but reading them
/// back through a stream here would test the query rather than the write, and
/// the write is the whole of ADR 0018 that can go wrong.
Future<({String? title, int? end})> _chapter(
  AppDatabase db,
  String bookId,
) async {
  final row = await (db.select(
    db.readingPositions,
  )..where((p) => p.bookId.equals(bookId))).getSingleOrNull();

  return (title: row?.chapterTitle, end: row?.chapterEndIndex);
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
    fixtureBook(
      id: id,
      title: 'Romeo and Juliet',
      author: 'William Shakespeare',
      wordCount: 25000,
    ),
    Uint8List.fromList([1, 2, 3]),
  );

  Future<void> save(
    String bookId, {
    required String block,
    required String hlc,
    int? tokenIndex,
    String? chapterTitle,
    int? chapterEndIndex,
  }) => repository.savePosition(
    bookId: bookId,
    locator: _at(block),
    hlc: hlc,
    tokenIndex: tokenIndex,
    chapterTitle: chapterTitle,
    chapterEndIndex: chapterEndIndex,
  );

  test('a saved position keeps the chapter it was given', () async {
    await addBook('book-1');

    await save(
      'book-1',
      block: 'block-7',
      hlc: '0000000000001-00000-here',
      tokenIndex: 400,
      chapterTitle: 'Act I, Scene II',
      chapterEndIndex: 900,
    );

    expect(await _chapter(db, 'book-1'), (title: 'Act I, Scene II', end: 900));
  });

  test('a save without a chapter clears the one before it', () async {
    await addBook('book-1');

    await save(
      'book-1',
      block: 'block-7',
      hlc: '0000000000001-00000-here',
      tokenIndex: 400,
      chapterTitle: 'Act I, Scene II',
      chapterEndIndex: 900,
    );

    // A reader who rewinds into front matter is in no chapter, and the
    // screen passes none. insertOnConflictUpdate leaves out columns the
    // companion omits, so this is the case that catches a companion built
    // without them: the title would survive beside a locator that has moved
    // away from it.
    await save(
      'book-1',
      block: 'block-1',
      hlc: '0000000000002-00000-here',
      tokenIndex: 12,
    );

    expect(await _chapter(db, 'book-1'), (title: null, end: null));
  });

  test('a remote position clears the chapter this device recorded', () async {
    await addBook('book-1');

    await save(
      'book-1',
      block: 'block-7',
      hlc: '0000000000001-00000-here',
      tokenIndex: 400,
      chapterTitle: 'Act I, Scene II',
      chapterEndIndex: 900,
    );

    // Nothing chapter-shaped is on the wire, so a position from another
    // device says only where the reader is. Keeping the old title would
    // pair a chapter from where they used to be with a place they are now,
    // on the one device that can tell the difference and does not.
    await repository.applyRemotePosition(
      bookId: 'book-1',
      locator: _at('block-40'),
      hlc: '0000000000005-00000-other',
      tokenIndex: 8000,
    );

    expect(await _chapter(db, 'book-1'), (title: null, end: null));
  });

  test('a stale remote position leaves the local chapter alone', () async {
    await addBook('book-1');

    await save(
      'book-1',
      block: 'block-7',
      hlc: '0000000000009-00000-here',
      tokenIndex: 400,
      chapterTitle: 'Act I, Scene II',
      chapterEndIndex: 900,
    );

    // Older stamp: the write is dropped before it reaches the row at all,
    // so the clearing above must not happen either. A device that ignores a
    // position has no business forgetting the chapter it kept.
    await repository.applyRemotePosition(
      bookId: 'book-1',
      locator: _at('block-2'),
      hlc: '0000000000003-00000-other',
      tokenIndex: 90,
    );

    expect(await _chapter(db, 'book-1'), (title: 'Act I, Scene II', end: 900));
  });

  test('a position drained for a new book arrives with no chapter', () async {
    await repository.applyRemotePosition(
      bookId: 'book-2',
      locator: _at('block-3'),
      hlc: '0000000000005-00000-other',
      tokenIndex: 900,
    );

    await addBook('book-2');

    // The book landed a moment ago and nothing has parsed it, so there is no
    // chapter to be had. PendingPositions carries no such columns at all.
    expect(await _chapter(db, 'book-2'), (title: null, end: null));
  });

  test('the outbox event carries no chapter', () async {
    await addBook('book-1');

    await save(
      'book-1',
      block: 'block-7',
      hlc: '0000000000001-00000-here',
      tokenIndex: 400,
      chapterTitle: 'Act I, Scene II',
      chapterEndIndex: 900,
    );

    final event = await (db.select(
      db.outboxEvents,
    )..where((e) => e.entityId.equals('book-1'))).getSingle();

    // The wire contract is unchanged by ADR 0018, and this is the assertion
    // that says so. A chapter is a fact about this device's parse of this
    // copy of the book; the service holds no copy and no other device holds
    // this one.
    expect(event.payloadJson, isNot(contains('chapter')));
    expect(event.payloadJson, contains('tokenIndex'));
  });
}
