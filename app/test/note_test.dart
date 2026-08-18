import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/book_progress.dart';
import 'package:app/reading/library_book.dart';
import 'package:drift/native.dart';
import 'package:epub_reader/epub_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

Uint8List _bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  group('BookSourceFormat.fromName', () {
    test('round-trips both values', () {
      expect(BookSourceFormat.fromName('epub'), BookSourceFormat.epub);
      expect(BookSourceFormat.fromName('note'), BookSourceFormat.note);
    });

    test('falls back to epub for anything unrecognised', () {
      // A build ahead of this one, or a row edited by hand. Falling back to
      // the format every row predates this column had is the same argument
      // the schema-8 migration's own default makes.
      expect(BookSourceFormat.fromName('audiobook'), BookSourceFormat.epub);
      expect(BookSourceFormat.fromName(''), BookSourceFormat.epub);
    });
  });

  group('LibraryBook.newNoteId', () {
    test('two ids issued in the same millisecond differ', () {
      final ids = {for (var i = 0; i < 100; i++) LibraryBook.newNoteId()};
      expect(ids, hasLength(100));
    });

    test('draws a full 32 bits of entropy', () {
      // The same regression guard ReadingProfile.newId carries: a draw that
      // silently narrowed would show up here as a short or constant suffix.
      final suffixes = <String>{};

      for (var i = 0; i < 200; i++) {
        final parts = LibraryBook.newNoteId().split('.');
        expect(parts, hasLength(3));

        final suffix = parts[2];
        expect(suffix, hasLength(8));

        final value = int.parse(suffix, radix: 16);
        expect(value, greaterThanOrEqualTo(0));
        expect(value, lessThanOrEqualTo(0xFFFFFFFF));

        suffixes.add(suffix);
      }

      expect(suffixes, hasLength(200));
    });
  });

  group('BookImporter.openNote', () {
    const importer = BookImporter();

    test('a blank line separates two paragraphs into two blocks', () async {
      final book = await importer.openNote(
        _bytesOf('First paragraph.\n\nSecond paragraph.'),
        id: 'note-1',
        title: 'A note',
      );

      final words = book.text.tokens.map((t) => t.text).toList();
      expect(words, ['First', 'paragraph.', 'Second', 'paragraph.']);

      // Two blocks, not one: a locator for the second paragraph must resolve
      // to a block distinct from the first, or every position saved partway
      // through a multi-paragraph note lands on the same block.
      final firstBlock = book.text.locatorAt(0)!.blockId;
      final secondBlock = book.text.locatorAt(2)!.blockId;
      expect(secondBlock, isNot(firstBlock));
    });

    test('a single line break inside a paragraph is not a boundary', () async {
      final book = await importer.openNote(
        _bytesOf('Line one\nline two, still one paragraph.'),
        id: 'note-1',
        title: 'A note',
      );

      // If the break split the text into two blocks, the second half would
      // start a new block; instead every token here comes from one.
      expect(book.text.blockCount, 1);
    });

    test('markup characters read back as typed, not as tags', () async {
      final book = await importer.openNote(
        _bytesOf('Use <b> tags & such, carefully.'),
        id: 'note-1',
        title: 'A note',
      );

      final words = book.text.tokens.map((t) => t.text).toList();
      // If these were parsed as markup rather than escaped first, `<b>`
      // would vanish as an unrecognised element and never reach a token.
      expect(words, contains('<b>'));
      expect(words, contains('&'));
    });

    test('a blank note has nothing to read', () {
      // The matcher applies to the Future itself, not a closure: openNote
      // returns immediately and the exception surfaces when compute's
      // isolate reports back, not when this line runs.
      expect(
        importer.openNote(_bytesOf('   \n\n  '), id: 'note-1', title: 'Empty'),
        throwsA(isA<EpubException>()),
      );
    });

    test('the id and title come from the caller, not the text', () async {
      final book = await importer.openNote(
        _bytesOf('Whatever the title says.'),
        id: 'note-42',
        title: 'A Chosen Title',
      );

      expect(book.id, 'note-42');
      expect(book.title, 'A Chosen Title');
    });

    test('reparsing the same text produces the same block id', () async {
      // The whole reason a note goes through HtmlNormalizer rather than a
      // bespoke path: block ids have to be stable across reopens for a saved
      // locator to keep resolving, the same guarantee ADR 0002 makes for an
      // EPUB.
      final bytes = _bytesOf('Paragraph one.\n\nParagraph two.');

      final first = await importer.openNote(bytes, id: 'note-1', title: 'A');
      final second = await importer.openNote(bytes, id: 'note-1', title: 'A');

      expect(
        first.text.locatorAt(2)!.blockId,
        second.text.locatorAt(2)!.blockId,
      );
    });
  });

  group('BookImporter.reopenStored', () {
    const importer = BookImporter();

    test(
      'dispatches a note to openNote using the caller-supplied title',
      () async {
        final book = await importer.reopenStored(
          _bytesOf('Some notes.'),
          sourceFormat: BookSourceFormat.note,
          id: 'note-1',
          title: 'Stored Title',
        );

        expect(book.id, 'note-1');
        expect(book.title, 'Stored Title');
      },
    );
  });

  group('note storage', () {
    late AppDatabase db;
    late LibraryRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = LibraryRepository(db);
    });

    tearDown(() => db.close());

    test('a stored note round-trips its format and title', () async {
      final bytes = _bytesOf('A note worth keeping.');

      await repo.addBook(
        id: 'note-1',
        title: 'Kept',
        bytes: bytes,
        wordCount: 4,
        sourceFormat: 'note',
      );

      final stored = await repo.storedBookOf('note-1');

      expect(stored, isNotNull);
      expect(stored!.sourceFormat, 'note');
      expect(stored.title, 'Kept');
      expect(stored.bytes, bytes);
    });

    test('an epub row round-trips its format the same way', () async {
      await repo.addBook(
        id: 'book-1',
        title: 'A Book',
        bytes: _bytesOf('irrelevant'),
        wordCount: 1,
        sourceFormat: 'epub',
      );

      final stored = await repo.storedBookOf('book-1');
      expect(stored!.sourceFormat, 'epub');
    });

    test('storedBookOf is null for a book not on this device', () async {
      expect(await repo.storedBookOf('missing'), isNull);
    });
  });

  group('editNote', () {
    late AppDatabase db;
    late LibraryRepository repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = LibraryRepository(db);

      await repo.addBook(
        id: 'note-1',
        title: 'Original title',
        bytes: _bytesOf('Original text.'),
        wordCount: 2,
        sourceFormat: 'note',
      );
    });

    tearDown(() => db.close());

    test(
      'rewrites title, bytes and wordCount without touching importedAt',
      () async {
        final before = (await repo.storedBookOf('note-1'))!;
        final importedBefore = await (db.select(
          db.books,
        )..where((b) => b.id.equals('note-1'))).getSingle();

        await repo.editNote(
          id: 'note-1',
          title: 'New title',
          bytes: _bytesOf('New text.'),
          wordCount: 2,
          resetProgress: false,
        );

        final after = (await repo.storedBookOf('note-1'))!;
        final importedAfter = await (db.select(
          db.books,
        )..where((b) => b.id.equals('note-1'))).getSingle();

        expect(after.title, 'New title');
        expect(after.bytes, isNot(before.bytes));
        // A plain update, not addBook's insertOnConflictUpdate: that path
        // rewrites importedAt to now on every call, which would be wrong for
        // an edit — it changes when the text was last written, not when the
        // note first arrived.
        expect(importedAfter.importedAt, importedBefore.importedAt);
        expect(importedAfter.updatedAt, isNotNull);
      },
    );

    test('resetProgress: false leaves a saved position alone', () async {
      await repo.savePosition(
        bookId: 'note-1',
        locator: const Locator(blockId: 'b', charOffset: 0, parserVersion: 1),
        hlc: '0000000000001-00000-a',
        tokenIndex: 1,
      );

      await repo.editNote(
        id: 'note-1',
        title: 'Original title',
        bytes: _bytesOf('Original text.'),
        wordCount: 2,
        resetProgress: false,
      );

      expect(await repo.positionOf('note-1'), isNotNull);
    });

    test('resetProgress: true drops the saved position', () async {
      await repo.savePosition(
        bookId: 'note-1',
        locator: const Locator(blockId: 'b', charOffset: 0, parserVersion: 1),
        hlc: '0000000000001-00000-a',
        tokenIndex: 1,
      );

      await repo.editNote(
        id: 'note-1',
        title: 'Original title',
        bytes: _bytesOf('Edited text.'),
        wordCount: 2,
        resetProgress: true,
      );

      expect(await repo.positionOf('note-1'), isNull);
    });

    test('resetProgress: true drops an unsent position event too', () async {
      await repo.savePosition(
        bookId: 'note-1',
        locator: const Locator(blockId: 'b', charOffset: 0, parserVersion: 1),
        hlc: '0000000000001-00000-a',
        tokenIndex: 1,
      );

      await repo.editNote(
        id: 'note-1',
        title: 'Original title',
        bytes: _bytesOf('Edited text.'),
        wordCount: 2,
        resetProgress: true,
      );

      // An event for the position just discarded would otherwise go out on
      // the next drain and write a locator back this note no longer
      // resolves.
      final pending = await repo.pendingEvents();
      expect(
        pending.where(
          (e) => e.entityType == 'position' && e.entityId == 'note-1',
        ),
        isEmpty,
      );
    });
  });

  group('BookSummary.progress', () {
    BookSummary summaryAt(int? tokenIndex, {int wordCount = 100}) =>
        BookSummary(
          id: 'b',
          title: 'T',
          wordCount: wordCount,
          importedAt: DateTime.utc(2026),
          sourceFormat: 'epub',
          tokenIndex: tokenIndex,
        );

    test('the last word of the book reads as 100%, not 99%', () {
      // tokenIndex is zero-based, so the last word of a 100-word book sits
      // at index 99 — the 100th word seen, not the 99th.
      expect(summaryAt(99).progress, 1.0);
    });

    test('the first word read is not 0%', () {
      expect(summaryAt(0).progress, closeTo(0.01, 0.0001));
    });

    test('no position is unknown, not 0%', () {
      expect(summaryAt(null).progress, isNull);
    });
  });

  group('noteDateLabel', () {
    BookSummary noteAt({DateTime? updatedAt}) => BookSummary(
      id: 'n',
      title: 'A note',
      wordCount: 5,
      importedAt: DateTime.utc(2026, 8, 18, 14, 5),
      sourceFormat: 'note',
      updatedAt: updatedAt,
    );

    test('null for anything that is not a note', () {
      final book = BookSummary(
        id: 'b',
        title: 'A Book',
        wordCount: 5,
        importedAt: DateTime.utc(2026, 8, 18, 14, 5),
        sourceFormat: 'epub',
      );

      expect(noteDateLabel(book), isNull);
    });

    test('says Added when it has never been edited', () {
      expect(noteDateLabel(noteAt()), startsWith('Added'));
    });

    test('says Edited once updatedAt is set', () {
      expect(
        noteDateLabel(noteAt(updatedAt: DateTime.utc(2026, 8, 19, 9, 30))),
        startsWith('Edited'),
      );
    });
  });
}
