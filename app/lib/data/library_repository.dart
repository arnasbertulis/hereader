import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'database.dart';

/// A book as the library list needs it: metadata without the bytes.
///
/// Loading blobs to draw a list would read every book into memory to render
/// a few titles. [LibraryRepository.watchLibrary] names its columns rather
/// than selecting rows so that stays true; it did not for a while, and the
/// comment outlived the arrangement it described.
///
/// `language` is stored on the book row but not carried here. Per-language
/// tokenizer settings are a real seam (ADR 0003) and the column exists for
/// them, but nothing reads a summary's language today, and a field nothing
/// reads reserves nothing.
class BookSummary {
  final String id;
  final String title;
  final String? author;
  final int wordCount;
  final Locator? position;
  final DateTime importedAt;

  /// How many tokens into the book the stored position is, when that is
  /// known. See ADR 0013: a hint for comparison and display, never something
  /// to navigate by.
  final int? tokenIndex;

  const BookSummary({
    required this.id,
    required this.title,
    required this.wordCount,
    required this.importedAt,
    this.author,
    this.position,
    this.tokenIndex,
  });

  /// Whether the reader has opened this book.
  bool get started => position != null;

  /// How far through the book the reader is, from 0 to 1, or null when that
  /// cannot be worked out.
  ///
  /// Null in three cases, and the interface says something different about
  /// each rather than drawing an empty bar for all of them: the book was
  /// never opened, the position came from a client older than ADR 0013 and
  /// carries no count, or the book row predates the wordCount column and
  /// reports zero. The last of those is why this checks the denominator
  /// rather than trusting it.
  double? get progress {
    final index = tokenIndex;
    if (index == null || wordCount <= 0) return null;

    return (index / wordCount).clamp(0.0, 1.0);
  }
}

/// How the library list is ordered.
///
/// `recentlyAdded` rather than "Recent", which reads as recently opened and
/// is not what this sorts by. Home orders by when a book was last read; the
/// library orders by when it arrived.
enum LibrarySort {
  recentlyAdded('Recently added'),
  title('Title'),
  progress('Progress');

  const LibrarySort(this.label);

  final String label;

  /// The sort stored under this name, falling back to the default for
  /// anything unrecognised. A preference written by a newer build, or a
  /// value edited by hand, orders the list rather than throwing.
  static LibrarySort byName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => recentlyAdded);
}

/// Orders two summaries under [sort].
///
/// In Dart rather than in the query. Progress is a ratio of two columns from
/// two tables that is null in three different ways, so expressing it in SQL
/// means a nullable division and an explicit nulls-last clause, and the other
/// two orders would then live in a different place from it. The list being
/// sorted is the one about to be laid out on screen.
int _compare(LibrarySort sort, BookSummary a, BookSummary b) {
  switch (sort) {
    case LibrarySort.recentlyAdded:
      return b.importedAt.compareTo(a.importedAt);

    case LibrarySort.title:
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());

    case LibrarySort.progress:
      final mine = a.progress;
      final theirs = b.progress;

      if (mine == null && theirs == null) {
        return b.importedAt.compareTo(a.importedAt);
      }
      // A book with no measurable progress sorts last under either
      // direction. It is not at zero percent; how far in it is is unknown.
      if (mine == null) return 1;
      if (theirs == null) return -1;

      return theirs.compareTo(mine);
  }
}

/// Everything the app stores locally.
///
/// The only place that knows about drift. Screens talk to this.
class LibraryRepository {
  final AppDatabase _db;

  LibraryRepository(this._db);

  // -- books ---------------------------------------------------------

  /// Library contents, most recently imported first, without book bytes.
  ///
  /// `selectOnly` with an explicit column list, not `select().join()`. A
  /// joined select includes every column of every table it reads, and
  /// `readTable` returns the whole row, so the earlier version pulled each
  /// book's entire EPUB into memory to render its title and threw it away
  /// again. Nothing was visibly wrong: the summaries were correct, and the
  /// cost was a blob read per book per emission of a stream that fires on
  /// every write to either table.
  ///
  /// The rule this leaves behind is narrow, because `bytes` is the only
  /// column here that costs anything: a query over Books that is not about
  /// the bytes names the columns it wants.
  Stream<List<BookSummary>> watchLibrary({
    LibrarySort sort = LibrarySort.recentlyAdded,
  }) {
    final table = _db.books;
    final positions = _db.readingPositions;

    final query = _db.selectOnly(table)
      ..join([
        leftOuterJoin(
          positions,
          positions.bookId.equalsExp(table.id),
          useColumns: false,
        ),
      ])
      ..addColumns([
        table.id,
        table.title,
        table.author,
        table.wordCount,
        table.importedAt,
        positions.blockId,
        positions.charOffset,
        positions.parserVersion,
        positions.tokenIndex,
      ])
      ..orderBy([OrderingTerm.desc(table.importedAt)]);

    return query.watch().map((rows) {
      final books = rows.map((row) {
        final blockId = row.read(positions.blockId);

        return BookSummary(
          id: row.read(table.id)!,
          title: row.read(table.title)!,
          author: row.read(table.author),
          wordCount: row.read(table.wordCount)!,
          importedAt: row.read(table.importedAt)!,
          position: blockId == null
              ? null
              : Locator(
                  blockId: blockId,
                  charOffset: row.read(positions.charOffset)!,
                  parserVersion: row.read(positions.parserVersion)!,
                ),
          tokenIndex: row.read(positions.tokenIndex),
        );
      }).toList();

      books.sort((a, b) => _compare(sort, a, b));

      return books;
    });
  }

  /// The stored cover for a book, or null when it has none.
  ///
  /// One book at a time rather than a stream of every cover. A library of
  /// forty books is forty images, and the grid needs the ones on screen.
  Future<Uint8List?> coverOf(String bookId) async {
    final row = await (_db.select(
      _db.bookCovers,
    )..where((c) => c.bookId.equals(bookId))).getSingleOrNull();

    return row?.bytes;
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
    Uint8List? coverBytes,
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

      if (coverBytes != null) {
        await _db
            .into(_db.bookCovers)
            .insertOnConflictUpdate(
              BookCoversCompanion.insert(bookId: id, bytes: coverBytes),
            );
      } else {
        // Re-importing an edition that no longer declares a cover should not
        // leave the old picture attached to the new book. A book with no
        // cover has no row.
        await (_db.delete(
          _db.bookCovers,
        )..where((c) => c.bookId.equals(id))).go();
      }

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
  ///
  /// Called often. ADR 0011 has the reader screen write every fifteen seconds
  /// as well as at every deliberate stop, which is why the queued event is
  /// coalesced below rather than appended to.
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
              // Written even when null, rather than left alone. The hint
              // describes this position; carrying the previous one forward
              // would pair a token index from where the reader used to be
              // with a locator for where they are now, and the service
              // measures divergence with it.
              tokenIndex: Value(tokenIndex),
              hlc: hlc,
              updatedAt: now,
            ),
          );

      await _coalescePositionEvents(bookId);

      await _enqueue(
        entityType: 'position',
        entityId: bookId,
        payload: {...locator.toJson(), 'tokenIndex': ?tokenIndex},
        hlc: hlc,
        now: now,
      );
    });
  }

  /// Drops queued position events for [bookId] that have never been sent.
  ///
  /// The outbox is an append-only log for profiles and a latest-value queue
  /// for positions, and that difference is about what the events mean rather
  /// than about volume. A create, a rename and a deletion each carry
  /// something no other profile event carries. A position event carries only
  /// "the reader is here now": the service resolves to the latest, every
  /// other device wants only where the reader ended up, and an intermediate
  /// position has no consumer anywhere in the system.
  ///
  /// With this, how often a position is written stops mattering to how much
  /// reaches the service. The queue holds one event per book regardless.
  ///
  /// `attempts == 0` is the guard, not an optimisation. An event that has
  /// already failed keeps its row and its counter, so a poison event can
  /// still be parked rather than having its count reset every time the reader
  /// moves — which is the failure ADR 0007 built parking to prevent.
  ///
  /// A push already in flight holds the rows it read, so deleting one here
  /// means markSent finds nothing for that id and the replacement goes out on
  /// the next drain.
  ///
  /// Assumes it is already inside a transaction.
  Future<void> _coalescePositionEvents(String bookId) =>
      (_db.delete(_db.outboxEvents)..where(
            (e) =>
                e.entityType.equals('position') &
                e.entityId.equals(bookId) &
                e.attempts.equals(0),
          ))
          .go();

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
    int? tokenIndex,
  }) async {
    await _db.transaction(() async {
      if (!await hasBook(bookId)) {
        await _holdPosition(
          bookId: bookId,
          locator: locator,
          hlc: hlc,
          tokenIndex: tokenIndex,
        );
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
              tokenIndex: Value(tokenIndex),
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
    int? tokenIndex,
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
            tokenIndex: Value(tokenIndex),
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
              tokenIndex: Value(held.tokenIndex),
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
