import 'dart:io';
import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every table the database currently holds, as SQLite reports them.
Future<List<String>> _tableNames(AppDatabase db) async {
  final rows = await db
      .customSelect("select name from sqlite_master where type = 'table'")
      .get();

  return rows.map((row) => row.read<String>('name')).toList();
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
      // Version 4 reconstructed rather than restored from a schema dump.
      // sync_state is the only difference between 4 and 5, so building the
      // current schema and adding that one table back is exact, not an
      // approximation — and it costs nothing to maintain.
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

      await legacy.customStatement(
        'create table sync_state ('
        'id integer not null default 0, '
        'last_seq integer not null default 0, '
        'last_sync_at integer, '
        'primary key (id))',
      );
      await legacy.customStatement(
        'insert into sync_state (id, last_seq) values (0, 42)',
      );

      // What drift reads to decide which upgrade steps to run.
      await legacy.customStatement('pragma user_version = 4');
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

  test('a fresh database is never given sync_state', () async {
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);

    expect(await _tableNames(db), isNot(contains('sync_state')));
  });
}
