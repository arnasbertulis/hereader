import 'dart:io';
import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// Every table the database currently holds, as SQLite reports them.
Future<List<String>> _tableNames(AppDatabase db) async {
  final rows = await db
      .customSelect("select name from sqlite_master where type = 'table'")
      .get();

  return rows.map((row) => row.read<String>('name')).toList();
}

/// Turns a database built from the current schema back into [version].
///
/// Every step since [version] is undone, then user_version is set so drift
/// runs those steps again on the next open. Reconstructing rather than
/// restoring a stored dump keeps every column this test does not care about
/// at whatever the schema says today.
///
/// The cost is a case here for each new migration step. Version 6 arrived
/// without one and the version 4 test failed on a duplicate column, because
/// a database built from the current schema already had what the step was
/// about to add. A step that only takes something away hides that.
Future<void> _revertTo(AppDatabase db, int version) async {
  if (version < 7) {
    await db.customStatement('drop table book_covers');
  }

  if (version < 6) {
    await db.customStatement(
      'alter table reading_positions drop column token_index',
    );
    await db.customStatement(
      'alter table pending_positions drop column token_index',
    );
  }

  if (version < 5) {
    await db.customStatement(
      'create table sync_state ('
      'id integer not null default 0, '
      'last_seq integer not null default 0, '
      'last_sync_at integer, '
      'primary key (id))',
    );
  }

  // What drift reads to decide which upgrade steps to run.
  await db.customStatement('pragma user_version = $version');
}

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    // A file rather than NativeDatabase.memory(): the migration only runs on
    // reopening, and an in-memory database does not survive being closed.
    dir = await Directory.systemTemp.createTemp('hereader_migration');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() => dir.delete(recursive: true));

  test(
    'upgrading from version 4 drops sync_state and keeps the books',
    () async {
      final legacy = AppDatabase(NativeDatabase(file));

      // The point of the test. A migration verified only against a fresh
      // database proves nothing about the installs that actually run it, and
      // ADR 0007 already flagged that gap without closing it.
      await LibraryRepository(legacy).addBook(
        id: 'book-1',
        title: 'Romeo and Juliet',
        author: 'William Shakespeare',
        bytes: Uint8List.fromList([1, 2, 3]),
        wordCount: 25000,
      );

      await _revertTo(legacy, 4);

      await legacy.customStatement(
        'insert into sync_state (id, last_seq) values (0, 42)',
      );
      await legacy.close();

      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final tables = await _tableNames(upgraded);
      expect(tables, isNot(contains('sync_state')));

      // A destructive step that took a neighbouring table with it would be a
      // far worse bug than the dead one it removes.
      expect(tables, contains('books'));
      expect(tables, contains('reading_positions'));

      final books = await upgraded.select(upgraded.books).get();
      expect(books, hasLength(1));
      expect(books.single.title, 'Romeo and Juliet');
    },
  );

  test('upgrading from version 5 adds the token index and keeps places', () async {
    final legacy = AppDatabase(NativeDatabase(file));
    final before = LibraryRepository(legacy);

    await before.addBook(
      id: 'book-1',
      title: 'Romeo and Juliet',
      author: 'William Shakespeare',
      bytes: Uint8List.fromList([1, 2, 3]),
      wordCount: 25000,
    );

    // Saved the way a version 5 client saved: a locator and a stamp, with
    // nowhere to put a hint.
    await before.savePosition(
      bookId: 'book-1',
      locator: Locator(blockId: 'block-7', charOffset: 40, parserVersion: 1),
      hlc: '0000000000001-00000-old',
    );

    await _revertTo(legacy, 5);
    await legacy.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);

    final rows = await upgraded.select(upgraded.readingPositions).get();
    expect(rows, hasLength(1));
    expect(rows.single.blockId, 'block-7');

    // Null, not zero. This row predates the column, so how far into the book
    // the reader had reached was never recorded, and zero would put them at
    // the first word.
    expect(rows.single.tokenIndex, isNull);

    // The column is writable, not merely declared. An addColumn that ran
    // against the wrong table would still leave the assertions above true.
    await LibraryRepository(upgraded).savePosition(
      bookId: 'book-1',
      locator: Locator(blockId: 'block-9', charOffset: 0, parserVersion: 1),
      hlc: '0000000000002-00000-new',
      tokenIndex: 812,
    );

    final after = await upgraded.select(upgraded.readingPositions).getSingle();
    expect(after.tokenIndex, 812);
  });

  test('upgrading from version 6 makes room for covers', () async {
    final legacy = AppDatabase(NativeDatabase(file));

    await LibraryRepository(legacy).addBook(
      id: 'book-1',
      title: 'Romeo and Juliet',
      author: 'William Shakespeare',
      bytes: Uint8List.fromList([1, 2, 3]),
      wordCount: 25000,
    );

    await _revertTo(legacy, 6);
    await legacy.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);

    expect(await _tableNames(upgraded), contains('book_covers'));

    // Empty, and the book that was already here is untouched. The upgrade
    // does not go looking inside stored EPUBs for pictures.
    expect(await upgraded.select(upgraded.bookCovers).get(), isEmpty);
    expect(await upgraded.select(upgraded.books).get(), hasLength(1));

    // Writable, and keyed to a book that exists. A create table that ran
    // against nothing would leave the assertions above true.
    await LibraryRepository(upgraded).addBook(
      id: 'book-1',
      title: 'Romeo and Juliet',
      bytes: Uint8List.fromList([1, 2, 3]),
      wordCount: 25000,
      coverBytes: Uint8List.fromList([9, 9, 9]),
    );

    final covers = await upgraded.select(upgraded.bookCovers).get();
    expect(covers.single.bytes, [9, 9, 9]);
  });

  test('a fresh database is never given sync_state', () async {
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);

    expect(await _tableNames(db), isNot(contains('sync_state')));
  });
}
