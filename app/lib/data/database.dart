import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Imported books.
///
/// The EPUB bytes are stored, not the parsed text. Parsed text is derived
/// data: bumping kParserVersion would invalidate every cached copy, and it
/// regenerates in a fraction of a second. Storing the source means the
/// current parser is always the single source of truth, and normalizer
/// improvements apply to books already in the library.
///
/// Bytes live in the database rather than on disk because iOS container
/// paths change between installs and the web has no filesystem at all. It
/// also makes deletion atomic: no orphaned files behind a removed row.
class Books extends Table {
  /// The book's own identifier where it has one, otherwise title and author.
  /// Shared across devices, so it must not be device-local.
  TextColumn get id => text()();

  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get language => text().nullable()();

  /// The original EPUB. Large books make for large rows; acceptable for
  /// text, noted as a limit for heavily illustrated volumes.
  BlobColumn get bytes => blob()();

  DateTimeColumn get importedAt => dateTime()();

  /// Cached so the library list does not parse every book to draw itself.
  IntColumn get wordCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Where the reader is in each book.
///
/// A separate table rather than columns on Books: positions are written
/// constantly and read once, they sync under different conflict rules than
/// metadata, and the outbox references them independently.
class ReadingPositions extends Table {
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();

  /// Locator fields, stored flat so they can be queried and compared.
  TextColumn get blockId => text()();
  IntColumn get charOffset => integer()();
  IntColumn get parserVersion => integer()();

  /// How many tokens into the book this position is.
  ///
  /// A hint, not part of the locator. The tokenizer decides what counts as a
  /// token, so this number moves when kParserVersion moves while the locator
  /// stays valid, and nothing may navigate by it. The service compares it to
  /// judge whether two devices have genuinely diverged, and a progress
  /// readout can use it without re-parsing the book.
  ///
  /// Nullable and without a default, because null and zero say different
  /// things: null is no recorded hint, which is every row written before this
  /// column and every event from a client that predates it, while zero is the
  /// first word of the book.
  IntColumn get tokenIndex => integer().nullable()();

  /// Hybrid logical clock stamp from the device that wrote this. Orders
  /// writes across devices without trusting wall clocks.
  TextColumn get hlc => text()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {bookId};
}

/// Positions from other devices for books this one has not imported.
///
/// The missing foreign key to Books is the entire reason this table exists
/// separately. ADR 0004 keeps book files on the device, so a position can
/// reach a device long before the book does — on web, where nothing is ever
/// transferred, that is every first sign-in.
///
/// Writing such a position straight into ReadingPositions fails the cascade
/// constraint. Dropping it instead loses the position permanently, because
/// sync.last_seq advances past the event and no later pull returns it.
/// Holding it here costs a locator and two integers per waiting book.
///
/// Drained into ReadingPositions in the same transaction that imports the
/// matching book, so the book never exists without the position that was
/// waiting for it.
class PendingPositions extends Table {
  TextColumn get bookId => text()();

  TextColumn get blockId => text()();
  IntColumn get charOffset => integer()();
  IntColumn get parserVersion => integer()();

  /// Carried through the wait, so a book that arrives later arrives with the
  /// reader's progress rather than with a place and no sense of how far in
  /// it is.
  IntColumn get tokenIndex => integer().nullable()();

  TextColumn get hlc => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {bookId};
}

/// Reading profiles, including forks of the built-in presets.
///
/// Built-ins are not stored: they live in code and are merged in at read
/// time, so improving a preset does not require a migration.
class StoredProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Pacing and presentation as JSON. The engine owns these shapes and
  /// already round-trips them; mirroring every field as a column would mean
  /// a migration for each new setting.
  TextColumn get pacingJson => text()();
  TextColumn get presentationJson => text()();

  IntColumn get rewindWords => integer().withDefault(const Constant(2))();

  /// Tombstone. The row outlives the delete so that a later-arriving older
  /// event has a stamp to lose against. Without it, an absent row and a row
  /// deleted a second ago look identical, and any device that was offline
  /// during the deletion would resurrect the profile on its next push.
  ///
  /// ADR 0005 requires this for every deletable entity. A forked profile is
  /// the first one a reader can actually remove.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  TextColumn get hlc => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// App-wide settings that are not part of a profile.
///
/// Sync bookkeeping lives here too — `sync.last_seq`, `sync.last_hlc`,
/// `sync.last_synced_at` — under the same read and write path as anything
/// else the app remembers. It is one row per key rather than one wide row,
/// so a new piece of bookkeeping costs an insert rather than a migration.
class Preferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  TextColumn get hlc => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Changes waiting to be sent to the server.
///
/// Included from the first schema version even though nothing drained it
/// then. Retrofitting an outbox after positions are already being written is
/// a migration; having the table from the start was free.
class OutboxEvents extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Client-generated and stable across retries. The server uses it to
  /// recognise a duplicate rather than applying an event twice when a
  /// response is lost.
  TextColumn get idempotencyKey => text().unique()();

  /// What changed: 'position', 'profile', 'preference', 'book_metadata'.
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();

  /// The event body, shaped by entityType.
  TextColumn get payloadJson => text()();

  /// Whether this event removes the entity rather than writing it. The wire
  /// format has always carried the field; nothing could set it until
  /// profiles became deletable, so the sender hardcoded false.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  TextColumn get hlc => text()();
  DateTimeColumn get createdAt => dateTime()();

  /// Incremented on each failed send. Lets a poison event be parked rather
  /// than blocking the queue behind it forever.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  TextColumn get lastError => text().nullable()();
}

/// Reading positions the service says two devices disagree about.
///
/// Mirrored locally rather than fetched on demand so the prompt survives
/// going offline: a reader who sees the question and then loses signal
/// should still be able to answer it.
class PositionConflicts extends Table {
  /// The service's id for this conflict. Resolving it means telling the
  /// service which side won, so the local row is keyed by the remote id.
  IntColumn get serverId => integer()();

  TextColumn get bookId => text()();

  /// Both candidate positions, whole, so the app can show what each one is.
  TextColumn get oursJson => text()();
  TextColumn get theirsJson => text()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {serverId};
}

@DriftDatabase(
  tables: [
    Books,
    ReadingPositions,
    PendingPositions,
    StoredProfiles,
    Preferences,
    OutboxEvents,
    PositionConflicts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'hereader',
              // Web has no native filesystem, so drift needs sqlite3 compiled to
              // WebAssembly plus a worker script to run it. Both files are
              // downloaded manually into app/web/ (drift doesn't generate them):
              // sqlite3.wasm from simolus3/sqlite3.dart releases, drift_worker.js
              // from simolus3/drift releases. Native platforms need no equivalent
              // setup — drift_flutter's defaults already handle those.
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ),
      );

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      // An install several versions behind runs these in order and keeps its
      // books. Every step through 4 only added something; version 5 is the
      // first that takes anything away.
      if (from < 2) {
        await m.createTable(positionConflicts);
      }
      if (from < 3) {
        await m.createTable(pendingPositions);
      }
      if (from < 4) {
        // Both columns carry a default, so rows already on disk are correct
        // without a backfill: every stored profile is live, and every queued
        // event is a write rather than a delete.
        await m.addColumn(storedProfiles, storedProfiles.deleted);
        await m.addColumn(outboxEvents, outboxEvents.deleted);
      }
      if (from < 5) {
        // sync_state held a single row carrying last_seq and last_sync_at,
        // and nothing ever read or wrote it: SyncEngine keeps both under
        // Preferences ('sync.last_seq', 'sync.last_synced_at') instead,
        // where the same read and write path serves every other setting.
        //
        // Dropped rather than merely undeclared. Leaving it on disk would
        // put a table in every existing install that no schema mentions and
        // no code explains, which is a worse artefact than the dead table
        // this removes. Nothing references it, so the drop cannot cascade.
        await m.deleteTable('sync_state');
      }
      if (from < 6) {
        // No default and no backfill. Every row already on disk was written
        // without a hint, and null records that; a default of zero would put
        // every existing reader at the first word of their book.
        await m.addColumn(readingPositions, readingPositions.tokenIndex);
        await m.addColumn(pendingPositions, pendingPositions.tokenIndex);
      }
    },
    beforeOpen: (details) async {
      // Foreign keys are off by default in SQLite, so the cascade on
      // ReadingPositions would silently not fire.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
