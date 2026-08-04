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

  /// Hybrid logical clock stamp from the device that wrote this. Orders
  /// writes across devices without trusting wall clocks.
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

  TextColumn get hlc => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// App-wide settings that are not part of a profile.
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

/// Sync bookkeeping. One row, enforced by a fixed primary key.
class SyncState extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();

  /// Highest server sequence number this device has pulled.
  IntColumn get lastSeq => integer().withDefault(const Constant(0))();

  DateTimeColumn get lastSyncAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Books,
    ReadingPositions,
    StoredProfiles,
    Preferences,
    OutboxEvents,
    PositionConflicts,
    SyncState,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'hereader'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await into(
        syncState,
      ).insert(SyncStateCompanion.insert(), mode: InsertMode.insertOrIgnore);
    },
    onUpgrade: (m, from, to) async {
      // Existing installs have every table except this one. Creating it
      // rather than recreating the database keeps the reader's books.
      if (from < 2) {
        await m.createTable(positionConflicts);
      }
    },
    beforeOpen: (details) async {
      // Foreign keys are off by default in SQLite, so the cascade on
      // ReadingPositions would silently not fire.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
