import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// A stamp in the wire format: `{millis:013d}-{counter:05d}-{deviceId}`.
///
/// The padding is the point. Comparison is lexicographic everywhere in the
/// app, so an unpadded millisecond would sort wrongly against a padded one
/// and these tests would pass for the wrong reason.
String stamp(int millis, {int counter = 0, String device = 'device-a'}) =>
    '${millis.toString().padLeft(13, '0')}-'
    '${counter.toString().padLeft(5, '0')}-$device';

const bookId = 'http://www.gutenberg.org/1513';

Locator locatorAt(int offset, {String block = 'b3a68770'}) =>
    Locator(blockId: block, charOffset: offset, parserVersion: 1);

void main() {
  late AppDatabase db;
  late LibraryRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepository(db);
  });

  tearDown(() => db.close());

  Future<void> importBook({String id = bookId}) => repository.addBook(
    id: id,
    title: 'Romeo and Juliet',
    bytes: Uint8List.fromList([1, 2, 3]),
    wordCount: 25_000,
    sourceFormat: 'epub',
  );

  group('foreign key enforcement', () {
    // Guards the PRAGMA in beforeOpen. Without it the cascade below silently
    // does nothing, and the bug this whole change exists for would write an
    // orphan row instead of failing loudly.
    test('a position for an absent book cannot be written directly', () {
      expect(
        db
            .into(db.readingPositions)
            .insert(
              ReadingPositionsCompanion.insert(
                bookId: bookId,
                blockId: 'b3a68770',
                charOffset: 165,
                parserVersion: 1,
                hlc: stamp(1000),
                updatedAt: DateTime.utc(2026),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('removing a book removes its position', () async {
      await importBook();
      await repository.savePosition(
        bookId: bookId,
        locator: locatorAt(165),
        hlc: stamp(1000),
      );

      await repository.removeBook(bookId);

      expect(await repository.positionOf(bookId), isNull);
    });
  });

  group('a remote position for a book this device does not have', () {
    test('is held rather than throwing', () async {
      await repository.applyRemotePosition(
        bookId: bookId,
        locator: locatorAt(165),
        hlc: stamp(1000),
      );

      expect(await repository.positionOf(bookId), isNull);
      expect(await repository.pendingPositionOf(bookId), isNotNull);
      expect((await repository.pendingPositionOf(bookId))!.charOffset, 165);
    });

    test('a newer stamp replaces a held position', () async {
      await repository.applyRemotePosition(
        bookId: bookId,
        locator: locatorAt(165),
        hlc: stamp(1000),
      );
      await repository.applyRemotePosition(
        bookId: bookId,
        locator: locatorAt(900),
        hlc: stamp(2000),
      );

      expect((await repository.pendingPositionOf(bookId))!.charOffset, 900);
    });

    test('an older stamp does not replace a held position', () async {
      await repository.applyRemotePosition(
        bookId: bookId,
        locator: locatorAt(900),
        hlc: stamp(2000),
      );
      await repository.applyRemotePosition(
        bookId: bookId,
        locator: locatorAt(165),
        hlc: stamp(1000),
      );

      expect((await repository.pendingPositionOf(bookId))!.charOffset, 900);
    });

    test('holds nothing for other books', () async {
      await repository.applyRemotePosition(
        bookId: bookId,
        locator: locatorAt(165),
        hlc: stamp(1000),
      );

      expect(await repository.pendingPositionOf('some-other-book'), isNull);
    });
  });

  group('importing the book the held position was waiting for', () {
    test('moves it into place and clears the held row', () async {
      await repository.applyRemotePosition(
        bookId: bookId,
        locator: locatorAt(165),
        hlc: stamp(1000),
      );

      await importBook();

      expect((await repository.positionOf(bookId))!.charOffset, 165);
      expect(await repository.pendingPositionOf(bookId), isNull);
    });

    test('keeps the originating stamp rather than restamping', () async {
      const remote = '0000000001000-00000-device-b';

      await repository.applyRemotePosition(
        bookId: bookId,
        locator: locatorAt(165),
        hlc: remote,
      );
      await importBook();

      final row = await (db.select(
        db.readingPositions,
      )..where((p) => p.bookId.equals(bookId))).getSingle();

      // Restamping here would let a place read on another device days ago
      // outrank a newer read elsewhere, purely because this device imported
      // the file late.
      expect(row.hlc, remote);
    });

    test('the drained position appears in the library list', () async {
      await repository.applyRemotePosition(
        bookId: bookId,
        locator: locatorAt(165),
        hlc: stamp(1000),
      );
      await importBook();

      final library = await repository.watchLibrary().first;

      expect(library.single.position!.charOffset, 165);
    });

    test('does not queue an outbox event', () async {
      await repository.applyRemotePosition(
        bookId: bookId,
        locator: locatorAt(165),
        hlc: stamp(1000),
      );
      await importBook();

      // The service already has this write. Sending it back would loop, one
      // event per round trip.
      expect(await repository.pendingEvents(), isEmpty);
    });

    test('a newer local position survives a re-import', () async {
      await importBook();
      await repository.savePosition(
        bookId: bookId,
        locator: locatorAt(900),
        hlc: stamp(3000),
      );

      // Removing the book drops the position but leaves the held row, so
      // re-importing must not resurrect the older place.
      await repository.applyRemotePosition(
        bookId: 'another-book',
        locator: locatorAt(10),
        hlc: stamp(1000),
      );
      await db
          .into(db.pendingPositions)
          .insert(
            PendingPositionsCompanion.insert(
              bookId: bookId,
              blockId: 'b3a68770',
              charOffset: 165,
              parserVersion: 1,
              hlc: stamp(1000),
              updatedAt: DateTime.utc(2026),
            ),
          );

      await importBook();

      expect((await repository.positionOf(bookId))!.charOffset, 900);
      expect(await repository.pendingPositionOf(bookId), isNull);
    });
  });

  group('a remote position for a book this device has', () {
    test('is written straight through', () async {
      await importBook();

      await repository.applyRemotePosition(
        bookId: bookId,
        locator: locatorAt(165),
        hlc: stamp(1000),
      );

      expect((await repository.positionOf(bookId))!.charOffset, 165);
      expect(await repository.pendingPositionOf(bookId), isNull);
    });

    test('an older stamp does not move the reader backwards', () async {
      await importBook();
      await repository.savePosition(
        bookId: bookId,
        locator: locatorAt(900),
        hlc: stamp(2000),
      );

      await repository.applyRemotePosition(
        bookId: bookId,
        locator: locatorAt(165),
        hlc: stamp(1000),
      );

      expect((await repository.positionOf(bookId))!.charOffset, 900);
    });
  });

  group('sign-out', () {
    test('clears held positions', () async {
      await repository.applyRemotePosition(
        bookId: bookId,
        locator: locatorAt(165),
        hlc: stamp(1000),
      );

      await repository.clearPendingPositions();

      expect(await repository.pendingPositionOf(bookId), isNull);
    });
  });

  group('hasBook', () {
    test('is false for a book only a position refers to', () async {
      await repository.applyRemotePosition(
        bookId: bookId,
        locator: locatorAt(165),
        hlc: stamp(1000),
      );

      expect(await repository.hasBook(bookId), isFalse);
    });

    test('is true once the book is imported', () async {
      await importBook();

      expect(await repository.hasBook(bookId), isTrue);
    });
  });
}
