import 'package:drift/drift.dart';

import 'database.dart';

/// Reads and writes sync's own bookkeeping — [SyncCursor] — the only table
/// it may use for that.
///
/// One-shot `read()`/`write()` over the single row created in
/// [AppDatabase.migration]'s `onCreate`. No stream/watch method: nothing
/// subscribes to the persisted row directly, since the settings and sync
/// screens' live updates come from `SyncEngine.state`, and the persisted
/// value is only ever read once, as a bootstrap value.
///
/// No method here can reach [OutboxEvents]. That is the point: the
/// guarantee that this bookkeeping never leaves the device, previously a
/// convention enforced by `setPreference`'s `sync: false` default at every
/// call site, is now a fact about what this type can do at all.
class SyncCursorDao {
  final AppDatabase _db;

  /// The only row. A table rather than a column on some other table, so a
  /// stream over a reader preference is never invalidated by a write here.
  static const _rowId = 0;

  SyncCursorDao(this._db);

  /// The persisted cursor. Always present: seeded at `onCreate`, and by the
  /// version 11 migration for every install that predates it.
  Future<SyncCursorRow> read() => (_db.select(
    _db.syncCursor,
  )..where((c) => c.id.equals(_rowId))).getSingle();

  /// Updates whichever fields are given, leaving the rest as they are.
  Future<void> write({
    Value<int> lastSeq = const Value.absent(),
    Value<String?> lastHlc = const Value.absent(),
    Value<DateTime?> lastSyncedAt = const Value.absent(),
  }) => (_db.update(_db.syncCursor)..where((c) => c.id.equals(_rowId))).write(
    SyncCursorCompanion(
      lastSeq: lastSeq,
      lastHlc: lastHlc,
      lastSyncedAt: lastSyncedAt,
    ),
  );
}
