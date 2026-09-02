import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';

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

  /// The original EPUB, or a note's text as UTF-8. Large books make for
  /// large rows; acceptable for text, noted as a limit for heavily
  /// illustrated volumes.
  BlobColumn get bytes => blob()();

  /// 'epub' or 'note'. Decides how [bytes] is parsed on open: an EPUB is a
  /// zip archive, a note is UTF-8 text run through the same
  /// [kParserVersion]'d normalizer a spine document gets. Defaulted to
  /// 'epub' rather than left nullable, since every row on disk before this
  /// column existed was one.
  TextColumn get sourceFormat => text().withDefault(const Constant('epub'))();

  DateTimeColumn get importedAt => dateTime()();

  /// When a note's own text was last written, distinct from [importedAt].
  ///
  /// Null rather than defaulted to [importedAt] at creation: those are two
  /// different facts that happen to coincide at first, and a default would
  /// conflate "just imported" with "edited the instant it arrived". Null
  /// means never edited since import, which every EPUB stays forever and a
  /// note stays until its first edit — the library reads one or the other
  /// off whichever of the two columns is the more recent true fact.
  DateTimeColumn get updatedAt => dateTime().nullable()();

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

  /// The chapter this position is in, as the book itself names it.
  ///
  /// Device-local and never synced. A chapter is resolved from this device's
  /// parse of this copy of the book (ADR 0010), so there is nothing another
  /// device could do with one, and it is written only by the reader screen —
  /// every other path that touches this row clears it rather than leaving a
  /// title from where the reader used to be beside a locator for where they
  /// are now. See ADR 0018.
  ///
  /// Nullable and without a default, for the same reason [tokenIndex] is:
  /// null is no recorded chapter, which is every row written before this
  /// column, every book that declares no table of contents, every note, and
  /// every position that arrived from somewhere else.
  TextColumn get chapterTitle => text().nullable()();

  /// The token that chapter ends before, exclusive.
  ///
  /// Null exactly when [chapterTitle] is, and written in the same statement,
  /// so the pair is never half-true. An end rather than a start: the screens
  /// that read it are asking how much of the chapter is left, and they
  /// already hold the index the reader is at.
  IntColumn get chapterEndIndex => integer().nullable()();

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

/// Cover images, one per book that declares one.
///
/// A table rather than a column on Books. SQLite stores a row's columns
/// together, and the Books row already carries the whole EPUB, so a cover
/// there would be rewritten whenever anything about the book was written and
/// read by any query that does not name its columns. Keeping it separate also
/// means a book without a cover costs no row at all rather than a null blob.
///
/// Cascades from Books, so removing a book takes its cover the same way it
/// takes its position.
class BookCovers extends Table {
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();

  /// The image exactly as the EPUB stored it, neither re-encoded nor
  /// downscaled. Decoding at tile size is an argument at render time, and a
  /// resize during import would spend the thing import has least of on web,
  /// which is main-thread milliseconds.
  BlobColumn get bytes => blob()();

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
/// One row per key rather than one wide row, so a new setting costs an
/// insert rather than a migration.
///
/// Sync's own bookkeeping does not live here (see [SyncCursor]): a stream
/// watching this table for a reader preference would otherwise be woken by
/// sync's housekeeping every time sync ran, since Drift invalidates a
/// watched query on any write to a table it joins, not on the specific key
/// that changed.
class Preferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  TextColumn get hlc => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Sync's own bookkeeping: how far it has pulled, the clock stamp to
/// restore on restart, and when it last ran.
///
/// A single row, present from [AppDatabase.migration]'s `onCreate`. Kept out
/// of [Preferences] on purpose — see that table's own comment — so that a
/// stream over a reader preference is disturbed only by a reader preference
/// actually changing.
///
/// No `hlc` column. That column on [Preferences] and [StoredProfiles] exists
/// to support entities that sync, and rows here never do: see
/// [SyncCursorDao], whose accessor has no code path that can reach
/// [OutboxEvents] at all.
@DataClassName('SyncCursorRow')
class SyncCursor extends Table {
  /// Always `0`. A table rather than a wider row on some other table so a
  /// stream can watch reader preferences without watching this too.
  ///
  /// `withDefault` alone does not make an omitted insert land on `0`: a
  /// lone `INTEGER PRIMARY KEY` column is a SQLite rowid alias, and an
  /// insert that leaves it out gets the next free rowid (1, 2, ...) rather
  /// than the column default. Every insert into this table passes
  /// `id: const Value(0)` explicitly.
  IntColumn get id => integer().withDefault(const Constant(0))();

  /// How far this device has pulled. `0` before the first successful pull.
  IntColumn get lastSeq => integer().withDefault(const Constant(0))();

  /// The hybrid-logical-clock stamp to restore on restart, or null before
  /// this device has ever issued one.
  TextColumn get lastHlc => text().nullable()();

  /// When sync last completed, or null before it ever has.
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
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
    BookCovers,
    StoredProfiles,
    Preferences,
    SyncCursor,
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
                // drift_flutter's own default onResult unconditionally
                // print()s the storage tier and any missing browser
                // features straight to the console. Falling back to
                // sharedIndexedDb is expected on browsers without drift's
                // preferred OPFS access (Firefox, at review time) — not a
                // failure worth surfacing to every production reader's
                // console. Kept for local debugging only.
                onResult: (result) {
                  if (kDebugMode && result.missingFeatures.isNotEmpty) {
                    debugPrint(
                      'Using ${result.chosenImplementation} due to missing '
                      'browser features: ${result.missingFeatures}',
                    );
                  }
                },
              ),
            ),
      );

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();

      // The single row SyncCursorDao reads and writes for the rest of the
      // app's life. createAll() only creates the (empty) table.
      await into(
        syncCursor,
      ).insert(SyncCursorCompanion.insert(id: const Value(0)));
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
        //
        // Reversed by the version 11 step below, once a watched query over
        // Preferences made sharing that table with this bookkeeping a
        // problem this migration's own reasoning did not anticipate.
        await m.deleteTable('sync_state');
      }
      if (from < 6) {
        // No default and no backfill. Every row already on disk was written
        // without a hint, and null records that; a default of zero would put
        // every existing reader at the first word of their book.
        await m.addColumn(readingPositions, readingPositions.tokenIndex);
        await m.addColumn(pendingPositions, pendingPositions.tokenIndex);
      }
      if (from < 7) {
        // Created empty. The covers of books already imported are still
        // inside their stored EPUBs, and extracting them here would unzip
        // and walk every book in the library during the first frame after an
        // update.
        await m.createTable(bookCovers);
      }
      if (from < 8) {
        // Backfilled to 'epub' rather than left null: every row on disk
        // before notes existed was an EPUB, and a default here means
        // existing books keep opening through the same parse path they
        // always have.
        await m.addColumn(books, books.sourceFormat);
      }
      if (from < 9) {
        // No backfill: every row on disk before this column existed has
        // never been edited through it, which is exactly what null means
        // here. Nothing needs to change for it to already be correct.
        await m.addColumn(books, books.updatedAt);
      }
      if (from < 10) {
        // No backfill, and none is possible: a chapter comes out of parsing
        // the book, and working one out for every stored position here would
        // unzip and tokenize the whole library during the first frame after
        // an update — on web, on the main thread. Null is also the honest
        // value, since no chapter was recorded when these rows were written.
        //
        // ReadingPositions only. A held position (PendingPositions) arrived
        // from another device and never had a chapter to carry.
        await m.addColumn(readingPositions, readingPositions.chapterTitle);
        await m.addColumn(readingPositions, readingPositions.chapterEndIndex);
      }
      if (from < 11) {
        // The reverse of the version 5 step above: sync's bookkeeping moves
        // back out of Preferences into its own table, SyncCursor, because a
        // stream over a reader preference joined against Preferences was
        // woken by sync's housekeeping every time sync ran, not only when a
        // preference actually changed. Version 5 shared the table for a
        // single read/write path; that reasoning does not survive a watched
        // query.
        //
        // Existing values move rather than reset, so updating does not cost
        // an install its progress and force a full resync. Moved and
        // deleted in the same step, so the fact is never held in two places
        // at once.
        await m.createTable(syncCursor);

        final rows =
            await (select(preferences)..where(
                  (p) => p.key.isIn(const [
                    'sync.last_seq',
                    'sync.last_hlc',
                    'sync.last_synced_at',
                  ]),
                ))
                .get();

        int? lastSeq;
        String? lastHlc;
        DateTime? lastSyncedAt;
        for (final row in rows) {
          switch (row.key) {
            case 'sync.last_seq':
              lastSeq = int.tryParse(row.value);
            case 'sync.last_hlc':
              lastHlc = row.value;
            case 'sync.last_synced_at':
              lastSyncedAt = DateTime.tryParse(row.value);
          }
        }

        await into(syncCursor).insert(
          SyncCursorCompanion.insert(
            id: const Value(0),
            lastSeq: Value(lastSeq ?? 0),
            lastHlc: Value(lastHlc),
            lastSyncedAt: Value(lastSyncedAt),
          ),
        );

        await (delete(preferences)..where(
              (p) => p.key.isIn(const [
                'sync.last_seq',
                'sync.last_hlc',
                'sync.last_synced_at',
              ]),
            ))
            .go();
      }
    },
    beforeOpen: (details) async {
      // Foreign keys are off by default in SQLite, so the cascade on
      // ReadingPositions would silently not fire.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
