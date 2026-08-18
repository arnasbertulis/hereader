import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/reader_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

Future<String> _stamp() async => '0000000000001-00000-test';

Locator _at(int offset) =>
    Locator(blockId: 'block-1', charOffset: offset, parserVersion: 1);

TokenizedText _text() => TokenizedText.from(const [
  (id: 'one', text: 'Alpha beta gamma.'),
  (id: 'two', text: 'Delta epsilon zeta.'),
], parserVersion: 1);

void main() {
  group('the position outbox', () {
    late AppDatabase database;
    late LibraryRepository repo;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      repo = LibraryRepository(database);

      await repo.addBook(
        id: 'book-1',
        title: 'A Book',
        bytes: Uint8List.fromList([1, 2, 3]),
        wordCount: 100,
        sourceFormat: 'epub',
      );
    });

    tearDown(() => database.close());

    test('keeps only the latest unsent event for a book', () async {
      await repo.savePosition(
        bookId: 'book-1',
        locator: _at(10),
        hlc: '0000000000001-00000-a',
        tokenIndex: 5,
      );
      await repo.savePosition(
        bookId: 'book-1',
        locator: _at(90),
        hlc: '0000000000002-00000-a',
        tokenIndex: 40,
      );

      final events = await repo.pendingEvents();

      // Saving every fifteen seconds only stays affordable because of this.
      // An intermediate position has no consumer: the service resolves to
      // the latest and other devices want where the reader ended up.
      expect(events, hasLength(1));

      final payload = jsonDecode(events.single.payloadJson);
      expect(payload['charOffset'], 90);
      expect(payload['tokenIndex'], 40);

      // The position row itself is the latest too, not merely the queue.
      expect((await repo.positionOf('book-1'))!.charOffset, 90);
    });

    test('leaves another book alone', () async {
      await repo.addBook(
        id: 'book-2',
        title: 'Another Book',
        bytes: Uint8List.fromList([4, 5, 6]),
        wordCount: 100,
        sourceFormat: 'epub',
      );

      await repo.savePosition(
        bookId: 'book-1',
        locator: _at(10),
        hlc: '0000000000001-00000-a',
      );
      await repo.savePosition(
        bookId: 'book-2',
        locator: _at(20),
        hlc: '0000000000002-00000-a',
      );
      await repo.savePosition(
        bookId: 'book-1',
        locator: _at(30),
        hlc: '0000000000003-00000-a',
      );

      final events = await repo.pendingEvents();

      expect(events, hasLength(2));
      expect(events.map((e) => e.entityId).toSet(), {'book-1', 'book-2'});
    });

    test('does not reset an event that has already failed', () async {
      await repo.savePosition(
        bookId: 'book-1',
        locator: _at(10),
        hlc: '0000000000001-00000-a',
      );

      final first = (await repo.pendingEvents()).single;
      await repo.markFailed(first.id, 'service refused it');

      await repo.savePosition(
        bookId: 'book-1',
        locator: _at(90),
        hlc: '0000000000002-00000-a',
      );

      // Coalescing a failed event would clear its counter every time the
      // reader moved, so a genuinely poison event could never be parked —
      // which is the failure ADR 0007 built parking to prevent.
      final events = await repo.pendingEvents();
      expect(events, hasLength(2));
      expect(events.firstWhere((e) => e.id == first.id).attempts, 1);
    });

    test('leaves nothing behind when the book is removed', () async {
      await repo.savePosition(
        bookId: 'book-1',
        locator: _at(10),
        hlc: '0000000000001-00000-a',
      );

      await repo.removeBook('book-1');

      expect(await repo.positionOf('book-1'), isNull);
    });
  });

  group('the reader screen', () {
    late AppDatabase database;

    setUp(() => database = AppDatabase(NativeDatabase.memory()));
    tearDown(() => database.close());

    Widget reader(
      LibraryBook book,
      List<ReadingResult> saves, {
      int? resumeIndex,
    }) => MaterialApp(
      home: ReaderScreen(
        book: book,
        repository: LibraryRepository(database),
        issueStamp: _stamp,
        onSave: (result) async => saves.add(result),
      ),
    );

    testWidgets('records the place when the reader jumps to a chapter', (
      tester,
    ) async {
      final text = _text();
      final saves = <ReadingResult>[];

      await tester.pumpWidget(
        reader(
          LibraryBook(
            id: 'b',
            title: 'A Book',
            text: text,
            chapters: [
              Chapter(
                title: 'Chapter One',
                depth: 0,
                tokenIndex: text.startOfBlock('one')!,
              ),
              Chapter(
                title: 'Chapter Two',
                depth: 0,
                tokenIndex: text.startOfBlock('two')!,
              ),
            ],
          ),
          saves,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Chapters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chapter Two'));
      await tester.pumpAndSettle();

      // The seek stops the session, and every stop is a save. That one
      // rule covers the pause button, the chapter panel and the profile
      // switcher without any of them knowing about it.
      expect(saves, hasLength(1));
      expect(saves.single.tokenIndex, text.startOfBlock('two'));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets(
      'finishing a single-word book is recorded, even though the token '
      'index never changes',
      (tester) async {
        // _lastSavedIndex starts at the resume index (0, the only index
        // this text has), so the ordinary "index unchanged, nothing to
        // save" guard would otherwise suppress every write for this text
        // forever — reaching `finished` is what has to force one through.
        final text = TokenizedText.from(const [
          (id: 'one', text: 'Word'),
        ], parserVersion: 1);
        final saves = <ReadingResult>[];

        await tester.pumpWidget(
          reader(LibraryBook(id: 'b', title: 'A Book', text: text), saves),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(readerPlayButtonKey));
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();

        expect(saves, isNotEmpty);
        expect(saves.last.tokenIndex, 0);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );

    testWidgets('writes nothing while the reader has not moved', (
      tester,
    ) async {
      final saves = <ReadingResult>[];

      await tester.pumpWidget(
        reader(LibraryBook(id: 'b', title: 'A Book', text: _text()), saves),
      );
      await tester.pumpAndSettle();

      // Two ticks of the fifteen-second timer. A paused reader, or a book
      // opened and looked at, compares two integers and returns: no
      // transaction, no stamp, no queued event.
      await tester.pump(const Duration(seconds: 35));

      expect(saves, isEmpty);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}
