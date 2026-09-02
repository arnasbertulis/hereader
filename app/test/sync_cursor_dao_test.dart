import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/data/sync_cursor_dao.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repo;
  late SyncCursorDao cursor;

  setUp(() {
    db = AppDatabase(testExecutor());
    repo = LibraryRepository(db);
    cursor = SyncCursorDao(db);
  });

  tearDown(() => db.close());

  group('SyncCursorDao', () {
    test('starts at zero, with nothing yet recorded', () async {
      final row = await cursor.read();

      expect(row.lastSeq, 0);
      expect(row.lastHlc, isNull);
      expect(row.lastSyncedAt, isNull);
    });

    test('write() updates only the fields given', () async {
      await cursor.write(lastSeq: const Value(7));
      await cursor.write(lastHlc: const Value('stamp-1'));

      final row = await cursor.read();
      expect(
        row.lastSeq,
        7,
        reason:
            'a later write of a different field '
            'must not reset an earlier one',
      );
      expect(row.lastHlc, 'stamp-1');
    });

    test('a value can be written and read back', () async {
      final syncedAt = DateTime.utc(2026, 1, 1);
      await cursor.write(
        lastSeq: const Value(42),
        lastHlc: const Value('0000000000001-00000-device'),
        lastSyncedAt: Value(syncedAt),
      );

      final row = await cursor.read();
      expect(row.lastSeq, 42);
      expect(row.lastHlc, '0000000000001-00000-device');
      // toUtc() rather than a direct DateTime comparison: Drift reads a
      // stored instant back as local time, and DateTime's own == treats a
      // UTC and a local DateTime as unequal even when they name the same
      // instant.
      expect(row.lastSyncedAt?.toUtc(), syncedAt);
    });

    test('writing through it never reaches the outbox', () async {
      // This is the guarantee that used to be a convention enforced at
      // every setPreference call site by its `sync: false` default. Here it
      // is structural: nothing on this type can enqueue an outbox event at
      // all.
      await cursor.write(
        lastSeq: const Value(42),
        lastHlc: const Value('0000000000001-00000-device'),
        lastSyncedAt: Value(DateTime.utc(2026, 1, 1)),
      );

      expect(await repo.pendingEvents(), isEmpty);
    });
  });
}
