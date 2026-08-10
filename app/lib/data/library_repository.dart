import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'database.dart';

/// A book as the library list needs it: metadata without the bytes.
///
/// Loading blobs to draw a list would read every book into memory to render
/// a few titles.
class BookSummary {
  final String id;
  final String title;
  final String? author;
  final String? language;
  final int wordCount;
  final Locator? position;
  final DateTime importedAt;

  const BookSummary({
    required this.id,
    required this.title,
    required this.wordCount,
    required this.importedAt,
    this.author,
    this.language,
    this.position,
  });
}

/// Everything the app stores locally.
///
/// The only place that knows about drift. Screens talk to this.
class LibraryRepository {
  final AppDatabase _db;

  LibraryRepository(this._db);

  // -- books ---------------------------------------------------------

  /// Library contents, most recently imported first, without book bytes.
  Stream<List<BookSummary>> watchLibrary() {
    final query = _db.select(_db.books).join([
      leftOuterJoin(
        _db.readingPositions,
        _db.readingPositions.bookId.equalsExp(_db.books.id),
      ),
    ])..orderBy([OrderingTerm.desc(_db.books.importedAt)]);

    return query.watch().map(
      (rows) => rows.map((row) {
        final book = row.readTable(_db.books);
        final position = row.readTableOrNull(_db.readingPositions);

        return BookSummary(
          id: book.id,
          title: book.title,
          author: book.author,
          language: book.language,
          wordCount: book.wordCount,
          importedAt: book.importedAt,
          position: position == null
              ? null
              : Locator(
                  blockId: position.blockId,
                  charOffset: position.charOffset,
                  parserVersion: position.parserVersion,
                ),
        );
      }).toList(),
    );
  }

  /// Stored EPUB bytes, or null if the book is not on this device.
  Future<Uint8List?> bytesOf(String bookId) async {
    final row = await (_db.select(
      _db.books,
    )..where((b) => b.id.equals(bookId))).getSingleOrNull();

    return row?.bytes;
  }

  /// Adds a book, or replaces it if the same edition is imported again.
  ///
  /// One transaction with the pending-position drain: a book that reached
  /// disk while its waiting position stayed behind would open at the start
  /// and then jump the moment the next sync ran.
  Future<void> addBook({
    required String id,
    required String title,
    required Uint8List bytes,
    required int wordCount,
    String? author,
    String? language,
  }) async {
    await _db.transaction(() async {
      await _db
          .into(_db.books)
          .insertOnConflictUpdate(
            BooksCompanion.insert(
              id: id,
              title: title,
              bytes: bytes,
              importedAt: DateTime.now().toUtc(),
              wordCount: Value(wordCount),
              author: Value(author),
              language: Value(language),
            ),
          );

      await _drainPendingPosition(id);
    });
  }

  /// Removes a book and, by cascade, its reading position.
  ///
  /// Any position held for this book stays. It is only reachable again if
  /// the reader re-imports the same edition, which is when they would want
  /// their place back.
  Future<void> removeBook(String bookId) =>
      (_db.delete(_db.books)..where((b) => b.id.equals(bookId))).go();

  /// Whether this device holds the book itself, not merely a position in it.
  ///
  /// Reads only the id column. Selecting the row would pull the EPUB blob
  /// into memory to answer a yes-or-no question.
  Future<bool> hasBook(String bookId) async {
    final row =
        await (_db.selectOnly(_db.books)
              ..addColumns([_db.books.id])
              ..where(_db.books.id.equals(bookId))
              ..limit(1))
            .getSingleOrNull();

    return row != null;
  }

  // -- positions -----------------------------------------------------

  Future<Locator?> positionOf(String bookId) async {
    final row = await (_db.select(
      _db.readingPositions,
    )..where((p) => p.bookId.equals(bookId))).getSingleOrNull();

    if (row == null) return null;

    return Locator(
      blockId: row.blockId,
      charOffset: row.charOffset,
      parserVersion: row.parserVersion,
    );
  }

  /// Records where the reader stopped, and queues the change for sync.
  ///
  /// Both writes happen in one transaction: a position that reaches disk
  /// without an outbox entry would never sync, and an outbox entry without
  /// a position would sync a change this device does not have.
  ///
  /// [tokenIndex] travels with the locator as a hint for how far into the
  /// book this is. The service cannot derive that itself — it has no copy of
  /// the book — and uses it to judge whether two devices have genuinely
  /// diverged or are a few words apart.
  Future<void> savePosition({
    required String bookId,
    required Locator locator,
    required String hlc,
    int? tokenIndex,
  }) async {
    await _db.transaction(() async {
      final now = DateTime.now().toUtc();

      await _db
          .into(_db.readingPositions)
          .insertOnConflictUpdate(
            ReadingPositionsCompanion.insert(
              bookId: bookId,
              blockId: locator.blockId,
              charOffset: locator.charOffset,
              parserVersion: locator.parserVersion,
              hlc: hlc,
              updatedAt: now,
            ),
          );

      await _enqueue(
        entityType: 'position',
        entityId: bookId,
        payload: {...locator.toJson(), 'tokenIndex': ?tokenIndex},
        hlc: hlc,
        now: now,
      );
    });
  }

  /// Writes a position that came from another device.
  ///
  /// Deliberately does not enqueue an outbox event. The service already has
  /// this write — that is where it came from — and sending it back would
  /// loop, with each round trip producing another event.
  ///
  /// If this device has not imported the book, the position is held rather
  /// than written. ReadingPositions.bookId cascades from Books, so writing
  /// it would fail the constraint outright, and skipping it would lose the
  /// position for good: sync.last_seq moves past the event and no later
  /// pull returns it.
  ///
  /// The stamp comparison is a second line of defence. The service has
  /// already decided which write wins, but an event can arrive after a newer
  /// local write on this device, and applying it would move the reader
  /// backwards.
  Future<void> applyRemotePosition({
    required String bookId,
    required Locator locator,
    required String hlc,
  }) async {
    await _db.transaction(() async {
      if (!await hasBook(bookId)) {
        await _holdPosition(bookId: bookId, locator: locator, hlc: hlc);
        return;
      }

      final existing = await (_db.select(
        _db.readingPositions,
      )..where((p) => p.bookId.equals(bookId))).getSingleOrNull();

      // Stamps are fixed-width, so comparing them as text gives the same
      // order as comparing the parts.
      if (existing != null && existing.hlc.compareTo(hlc) >= 0) return;

      await _db
          .into(_db.readingPositions)
          .insertOnConflictUpdate(
            ReadingPositionsCompanion.insert(
              bookId: bookId,
              blockId: locator.blockId,
              charOffset: locator.charOffset,
              parserVersion: locator.parserVersion,
              hlc: hlc,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
    });
  }

  /// The position waiting for a book this device has not imported.
  ///
  /// For tests and for anything that wants to tell a reader their place is
  /// already known before they import.
  Future<Locator?> pendingPositionOf(String bookId) async {
    final row = await (_db.select(
      _db.pendingPositions,
    )..where((p) => p.bookId.equals(bookId))).getSingleOrNull();

    if (row == null) return null;

    return Locator(
      blockId: row.blockId,
      charOffset: row.charOffset,
      parserVersion: row.parserVersion,
    );
  }

  /// Drops every held position. Call on sign-out, alongside clearing tokens:
  /// they belong to the account that has just gone away.
  Future<void> clearPendingPositions() => _db.delete(_db.pendingPositions).go();

  /// Parks a position until its book arrives.
  ///
  /// Keeps whichever stamp is greater, so a book that has been read on
  /// several devices while absent here holds only the latest place.
  ///
  /// Assumes it is already inside a transaction.
  Future<void> _holdPosition({
    required String bookId,
    required Locator locator,
    required String hlc,
  }) async {
    final held = await (_db.select(
      _db.pendingPositions,
    )..where((p) => p.bookId.equals(bookId))).getSingleOrNull();

    if (held != null && held.hlc.compareTo(hlc) >= 0) return;

    await _db
        .into(_db.pendingPositions)
        .insertOnConflictUpdate(
          PendingPositionsCompanion.insert(
            bookId: bookId,
            blockId: locator.blockId,
            charOffset: locator.charOffset,
            parserVersion: locator.parserVersion,
            hlc: hlc,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  /// Moves a held position into place now that the book exists.
  ///
  /// Carries the original stamp and timestamp across rather than issuing new
  /// ones. This write happened on another device at that time, and restamping
  /// it here would let an old place outrank a newer read elsewhere.
  ///
  /// Assumes it is already inside a transaction.
  Future<void> _drainPendingPosition(String bookId) async {
    final held = await (_db.select(
      _db.pendingPositions,
    )..where((p) => p.bookId.equals(bookId))).getSingleOrNull();

    if (held == null) return;

    final existing = await (_db.select(
      _db.readingPositions,
    )..where((p) => p.bookId.equals(bookId))).getSingleOrNull();

    // Re-importing a book the reader already had keeps the newer place.
    if (existing == null || existing.hlc.compareTo(held.hlc) < 0) {
      await _db
          .into(_db.readingPositions)
          .insertOnConflictUpdate(
            ReadingPositionsCompanion.insert(
              bookId: bookId,
              blockId: held.blockId,
              charOffset: held.charOffset,
              parserVersion: held.parserVersion,
              hlc: held.hlc,
              updatedAt: held.updatedAt,
            ),
          );
    }

    await (_db.delete(
      _db.pendingPositions,
    )..where((p) => p.bookId.equals(bookId))).go();
  }

  // -- profiles ------------------------------------------------------

  /// Built-in presets first, then the reader's own profiles by name.
  ///
  /// Presets are not stored, so changing one in code takes effect without a
  /// migration. A fork is an ordinary stored row.
  ///
  /// Tombstoned rows stay out. A stored row inside the built-in namespace
  /// also stays out: both the save path and the apply path refuse to write
  /// one, but being wrong costs the reader a duplicate entry in their list
  /// while the guard costs a string comparison.
  Stream<List<ReadingProfile>> watchProfiles() {
    final query = _db.select(_db.storedProfiles)
      ..where((p) => p.deleted.equals(false))
      ..orderBy([(p) => OrderingTerm.asc(p.name)]);

    return query.watch().map(_visible);
  }

  /// Presets first, then the reader's own.
  ///
  /// A stored row inside the built-in namespace is skipped. Both write paths
  /// refuse to create one, but being wrong costs the reader a duplicate entry
  /// in their list while the guard costs a string comparison.
  List<ReadingProfile> _visible(List<StoredProfile> rows) => [
    ...Presets.all,
    for (final row in rows)
      if (!row.id.startsWith(ReadingProfile.builtInIdPrefix)) _toProfile(row),
  ];

  /// The same list as [watchProfiles], read once.
  ///
  /// A direct query rather than `watchProfiles().first`. Building a query
  /// stream to read a value once sets up and tears down a subscription for
  /// nothing, and it makes the read wait on a timer: drift schedules one when
  /// a query stream is cancelled, and under `testWidgets` timers only fire
  /// while the tester is pumping, so an await outside a pump never returns.
  Future<List<ReadingProfile>> allProfiles() async {
    final rows =
        await (_db.select(_db.storedProfiles)
              ..where((p) => p.deleted.equals(false))
              ..orderBy([(p) => OrderingTerm.asc(p.name)]))
            .get();

    return _visible(rows);
  }

  ReadingProfile _toProfile(StoredProfile row) => ReadingProfile(
    id: row.id,
    name: row.name,
    pacing: PacingConfig.fromJson(
      jsonDecode(row.pacingJson) as Map<String, dynamic>,
    ),
    presentation: PresentationConfig.fromJson(
      jsonDecode(row.presentationJson) as Map<String, dynamic>,
    ),
    rewindWords: row.rewindWords,
  );

  /// Writes one of the reader's own profiles and queues it for sync.
  Future<void> saveProfile(
    ReadingProfile profile, {
    required String hlc,
  }) async {
    // isBuiltIn reads the id namespace, so this one check covers both a
    // preset passed in directly and a fork that kept a preset's id.
    if (profile.isBuiltIn) {
      throw ArgumentError('Built-in presets are not stored; fork one first.');
    }

    await _db.transaction(() async {
      final now = DateTime.now().toUtc();

      await _db
          .into(_db.storedProfiles)
          .insertOnConflictUpdate(
            StoredProfilesCompanion.insert(
              id: profile.id,
              name: profile.name,
              pacingJson: jsonEncode(profile.pacing.toJson()),
              presentationJson: jsonEncode(profile.presentation.toJson()),
              rewindWords: Value(profile.rewindWords),
              deleted: const Value(false),
              hlc: hlc,
              updatedAt: now,
            ),
          );

      await _enqueue(
        entityType: 'profile',
        entityId: profile.id,
        payload: profile.toJson(),
        hlc: hlc,
        now: now,
      );
    });
  }

  /// Tombstones a profile and tells the other devices it is gone.
  ///
  /// The event carries the whole profile rather than only its id. A device
  /// that never received the create, because it was offline for the
  /// profile's entire life, still has to write its own tombstone, and the
  /// columns backing that row are not nullable.
  Future<void> deleteProfile(String id, {required String hlc}) async {
    if (id.startsWith(ReadingProfile.builtInIdPrefix)) {
      throw ArgumentError('Built-in presets cannot be deleted.');
    }

    await _db.transaction(() async {
      final row = await (_db.select(
        _db.storedProfiles,
      )..where((p) => p.id.equals(id))).getSingleOrNull();

      // Nothing here, or already tombstoned. Enqueueing again would issue a
      // second delete for a profile every device has already dropped.
      if (row == null || row.deleted) return;

      final now = DateTime.now().toUtc();

      await (_db.update(
        _db.storedProfiles,
      )..where((p) => p.id.equals(id))).write(
        StoredProfilesCompanion(
          deleted: const Value(true),
          hlc: Value(hlc),
          updatedAt: Value(now),
        ),
      );

      await _enqueue(
        entityType: 'profile',
        entityId: id,
        payload: {
          'id': row.id,
          'name': row.name,
          'pacing': jsonDecode(row.pacingJson),
          'presentation': jsonDecode(row.presentationJson),
          'rewindWords': row.rewindWords,
        },
        hlc: hlc,
        now: now,
        deleted: true,
      );

      // Cleared in the same transaction rather than left for activeProfile()
      // to notice, so the reader is never briefly pointed at a profile this
      // device has just tombstoned.
      final active = await (_db.select(
        _db.preferences,
      )..where((p) => p.key.equals(activeProfileKey))).getSingleOrNull();

      if (active?.value == id) {
        await _clearActiveProfile();
      }
    });
  }

  /// Writes a profile that came from another device.
  ///
  /// Not enqueued, for the same reason as [applyRemotePosition]: the service
  /// is where this arrived from, and sending it back would loop.
  ///
  /// Whole-object last write wins, per ADR 0005. Two devices editing one
  /// profile concurrently means the app discards an edit rather than merging
  /// it: the pacing fields are a single coherent tuning rather than
  /// independent scalars, and merging field by field could leave the reader
  /// with a configuration neither device chose. A discarded font size is
  /// visible the moment they open settings and costs five seconds to redo.
  Future<void> applyRemoteProfile({
    required ReadingProfile profile,
    required String hlc,
    required bool deleted,
  }) async {
    // Refused quietly rather than thrown. A throw would count against the
    // skipped total the sync status shows, telling the reader a change was
    // lost when this one was turned away on purpose. Presets live in code
    // and nothing may replace them through sync.
    if (profile.isBuiltIn) return;

    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.storedProfiles,
      )..where((p) => p.id.equals(profile.id))).getSingleOrNull();

      // Stamps are fixed-width, so comparing them as text gives the same
      // order as comparing the parts. This is what stops a create that
      // arrives after a delete from resurrecting the profile.
      if (existing != null && existing.hlc.compareTo(hlc) >= 0) return;

      await _db
          .into(_db.storedProfiles)
          .insertOnConflictUpdate(
            StoredProfilesCompanion.insert(
              id: profile.id,
              name: profile.name,
              pacingJson: jsonEncode(profile.pacing.toJson()),
              presentationJson: jsonEncode(profile.presentation.toJson()),
              rewindWords: Value(profile.rewindWords),
              deleted: Value(deleted),
              hlc: hlc,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
    });
  }

  // -- active profile ------------------------------------------------

  /// Which profile the reader last chose, on this device only.
  ///
  /// Never synced. A phone read outdoors and a desktop in a dim room can
  /// reasonably want different profiles active, and a shared pointer would
  /// have each device pulling the other's choice out from under it. The
  /// profiles themselves sync; which one is in use does not.
  static const activeProfileKey = 'ui.active_profile';

  Future<void> setActiveProfile(String id, {required String hlc}) =>
      setPreference(activeProfileKey, id, hlc: hlc);

  /// The profile to read with, resolved against what is actually on this
  /// device.
  ///
  /// Falls back to [Presets.standard] by name rather than to the first entry
  /// in the list. A positional fallback would change as profiles come and go,
  /// which reads to the reader as the app reassigning their settings at
  /// random.
  ///
  /// A pointer that no longer resolves is cleared rather than left. A profile
  /// deleted on another device arrives here as a tombstone, and keeping the
  /// dead id would mean falling back on every single open forever after.
  Future<ReadingProfile> activeProfile() async {
    final id = await preference(activeProfileKey);
    if (id == null) return Presets.standard;

    for (final profile in await allProfiles()) {
      if (profile.id == id) return profile;
    }

    await _clearActiveProfile();
    return Presets.standard;
  }

  Future<void> _clearActiveProfile() => (_db.delete(
    _db.preferences,
  )..where((p) => p.key.equals(activeProfileKey))).go();

  // -- preferences ---------------------------------------------------

  Future<String?> preference(String key) async {
    final row = await (_db.select(
      _db.preferences,
    )..where((p) => p.key.equals(key))).getSingleOrNull();

    return row?.value;
  }

  /// Writes an app-wide setting.
  ///
  /// [sync] defaults to false, and the default is the point of the parameter.
  /// Sync bookkeeping lives in this table, and `sync.last_seq` reaching
  /// another device would have it skip events it had never pulled. The active
  /// profile pointer is device-local for its own reasons, below.
  ///
  /// Before this parameter existed the method simply never enqueued, so every
  /// preference was device-local by omission rather than by decision. Stating
  /// it at the call site means completing preference sync later cannot make a
  /// device-local setting start travelling by accident.
  Future<void> setPreference(
    String key,
    String value, {
    required String hlc,
    bool sync = false,
  }) async {
    if (!sync) {
      await _db
          .into(_db.preferences)
          .insertOnConflictUpdate(
            PreferencesCompanion.insert(key: key, value: value, hlc: hlc),
          );
      return;
    }

    await _db.transaction(() async {
      await _db
          .into(_db.preferences)
          .insertOnConflictUpdate(
            PreferencesCompanion.insert(key: key, value: value, hlc: hlc),
          );

      // Shaped to match what applyRemotePreference reads on the far side.
      await _enqueue(
        entityType: 'preference',
        entityId: key,
        payload: {'value': value},
        hlc: hlc,
        now: DateTime.now().toUtc(),
      );
    });
  }

  /// Writes a preference that came from another device.
  ///
  /// Not enqueued, for the same reason as [applyRemotePosition].
  Future<void> applyRemotePreference({
    required String key,
    required String value,
    required String hlc,
  }) async {
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.preferences,
      )..where((p) => p.key.equals(key))).getSingleOrNull();

      if (existing != null && existing.hlc.compareTo(hlc) >= 0) return;

      await _db
          .into(_db.preferences)
          .insertOnConflictUpdate(
            PreferencesCompanion.insert(key: key, value: value, hlc: hlc),
          );
    });
  }

  // -- position conflicts --------------------------------------------

  Future<void> recordPositionConflict({
    required int serverId,
    required String bookId,
    required String ours,
    required String theirs,
  }) async {
    await _db
        .into(_db.positionConflicts)
        .insertOnConflictUpdate(
          PositionConflictsCompanion.insert(
            serverId: Value(serverId),
            bookId: bookId,
            oursJson: ours,
            theirsJson: theirs,
            createdAt: DateTime.now().toUtc(),
          ),
        );
  }

  /// Divergences the reader has not settled yet.
  Stream<List<PositionConflict>> watchConflicts() =>
      _db.select(_db.positionConflicts).watch();

  Future<void> clearPositionConflict(int serverId) => (_db.delete(
    _db.positionConflicts,
  )..where((c) => c.serverId.equals(serverId))).go();

  // -- outbox --------------------------------------------------------

  /// Unsent events, oldest first, skipping any parked after repeated
  /// failures so one bad event cannot block the queue behind it.
  Future<List<OutboxEvent>> pendingEvents({int limit = 100}) {
    return (_db.select(_db.outboxEvents)
          ..where((e) => e.attempts.isSmallerThanValue(5))
          ..orderBy([(e) => OrderingTerm.asc(e.id)])
          ..limit(limit))
        .get();
  }

  /// How many events are waiting, for the app to show.
  Stream<int> watchPendingCount() {
    final count = _db.outboxEvents.id.count();

    return (_db.selectOnly(
      _db.outboxEvents,
    )..addColumns([count])).watchSingle().map((row) => row.read(count) ?? 0);
  }

  Future<void> markSent(Iterable<int> ids) =>
      (_db.delete(_db.outboxEvents)..where((e) => e.id.isIn(ids))).go();

  /// Records a failed send and counts the attempt.
  ///
  /// Written as a raw statement because the increment reads the current
  /// value: a read followed by a write could lose a count if two drains
  /// overlapped.
  Future<void> markFailed(int id, String error) async {
    await _db.customUpdate(
      'update outbox_events set attempts = attempts + 1, last_error = ? '
      'where id = ?',
      variables: [Variable.withString(error), Variable.withInt(id)],
      updates: {_db.outboxEvents},
    );
  }

  Future<void> _enqueue({
    required String entityType,
    required String entityId,
    required Map<String, dynamic> payload,
    required String hlc,
    required DateTime now,
    bool deleted = false,
  }) {
    return _db
        .into(_db.outboxEvents)
        .insert(
          OutboxEventsCompanion.insert(
            // The HLC stamp is unique per device and write, so it doubles as
            // the idempotency key rather than needing a separate uuid.
            idempotencyKey: '$entityType:$entityId:$hlc',
            entityType: entityType,
            entityId: entityId,
            payloadJson: jsonEncode(payload),
            deleted: Value(deleted),
            hlc: hlc,
            createdAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }
}
