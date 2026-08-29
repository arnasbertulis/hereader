import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../reading/library_book.dart';
import 'database.dart';

/// A stored book's bytes, plus what reopening it needs beyond them.
///
/// [sourceFormat] is carried as the raw column string ('epub' or 'note')
/// rather than as `BookSourceFormat`: that type lives in `reading/`, and this
/// file is the one place in the app that knows about drift, so it does not
/// import back into a layer that already imports it. Callers that need the
/// enum convert at the point they use it.
class StoredBook {
  final Uint8List bytes;
  final String sourceFormat;
  final String title;
  final String? author;

  const StoredBook({
    required this.bytes,
    required this.sourceFormat,
    required this.title,
    this.author,
  });
}

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

  /// 'epub' or 'note', carried as the raw column string for the same reason
  /// [StoredBook.sourceFormat] is: this file does not import the `reading/`
  /// layer that owns `BookSourceFormat`.
  final String sourceFormat;

  /// When a note's own text was last written, or null if it never has been.
  ///
  /// Null for every EPUB forever, since nothing ever rewrites one. See the
  /// column's own comment on [Books] for why this is not defaulted to
  /// [importedAt] instead.
  final DateTime? updatedAt;

  /// When the reader last saved a place in this book, or null when they
  /// never have.
  ///
  /// Home orders on this and the library orders on [importedAt], which is
  /// why both are carried rather than one date that means whichever the
  /// caller assumed. A book with no position row has no reading date at all,
  /// and Home falls back to the import rather than inventing one.
  final DateTime? lastReadAt;

  /// How many tokens into the book the stored position is, when that is
  /// known. See ADR 0013: a hint for comparison and display, never something
  /// to navigate by.
  final int? tokenIndex;

  /// The chapter the stored position is in, as the book names it, or null
  /// when this device has not recorded one.
  ///
  /// Null is ordinary rather than exceptional: a note, a book declaring no
  /// table of contents, a reader still in front matter, and a position that
  /// arrived from another device all have no chapter. See ADR 0018.
  final String? chapterTitle;

  /// The token that chapter ends before, exclusive. Null exactly when
  /// [chapterTitle] is.
  final int? chapterEndIndex;

  const BookSummary({
    required this.id,
    required this.title,
    required this.wordCount,
    required this.importedAt,
    required this.sourceFormat,
    this.updatedAt,
    this.author,
    this.position,
    this.tokenIndex,
    this.chapterTitle,
    this.chapterEndIndex,
    this.lastReadAt,
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
  ///
  /// `tokenIndex + 1`, not `tokenIndex`: the index is the zero-based token
  /// the reader is *at*, so the last word of the book sits at
  /// `wordCount - 1` and reads as 100% only once the count of words already
  /// seen — one more than that index — is what gets divided. Matches
  /// `TokenizedText.progressAt`, which the reader screen's own progress bar
  /// already uses; this used to be a second, uncorrected copy of the same
  /// formula, so a finished book or note showed 99% rather than 100%.
  double? get progress {
    final index = tokenIndex;
    if (index == null || wordCount <= 0) return null;

    return ((index + 1) / wordCount).clamp(0.0, 1.0);
  }
}

/// How the library list is ordered.
///
/// `recentlyAdded` rather than "Recent", which reads as recently opened and
/// is not what this sorts by. Home orders by when a book was last read; the
/// library orders by when it arrived.
///
/// Each value names both ends of itself rather than carrying an ascending
/// flag. Ascending means opposite things here: the useful end of a date is
/// the newest and the useful end of a title is the first letter, so a shared
/// direction would default to descending for two of these and ascending for
/// the third. [endLabel] lets the control say which end the reader is at in
/// the terms of the field they picked.
enum LibrarySort {
  recentlyAdded('Recently added', 'Newest first', 'Oldest first'),
  title('Title', 'A to Z', 'Z to A'),
  progress('Progress', 'Most read first', 'Least read first');

  const LibrarySort(this.label, this._nearEnd, this._farEnd);

  final String label;

  final String _nearEnd;
  final String _farEnd;

  /// What sits at the top of the list right now, in the reader's words.
  String endLabel({required bool reversed}) => reversed ? _farEnd : _nearEnd;

  /// The sort stored under this name, falling back to the default for
  /// anything unrecognised. A preference written by a newer build, or a
  /// value edited by hand, orders the list rather than throwing.
  static LibrarySort byName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => recentlyAdded);
}

/// Orders two summaries under [sort], with [reversed] flipping the result.
///
/// In Dart rather than in the query. Progress is a ratio of two columns from
/// two tables that is null in three different ways, so expressing it in SQL
/// means a nullable division and an explicit nulls-last clause, and the other
/// two orders would then live in a different place from it. The list being
/// sorted is the one about to be laid out on screen.
///
/// [reversed] multiplies the comparison rather than being decided per branch,
/// so a field cannot reverse in one direction and not the other. The one
/// thing it does not reach is a book whose progress is unknown: see below.
int _compare(
  LibrarySort sort,
  BookSummary a,
  BookSummary b, {
  required bool reversed,
}) {
  final flip = reversed ? -1 : 1;

  switch (sort) {
    case LibrarySort.recentlyAdded:
      return flip * b.importedAt.compareTo(a.importedAt);

    case LibrarySort.title:
      return flip * a.title.toLowerCase().compareTo(b.title.toLowerCase());

    case LibrarySort.progress:
      final mine = a.progress;
      final theirs = b.progress;

      // Two books nobody has opened, ordered by arrival. Not flipped: this
      // decides the order inside the unknown group, and that group stays at
      // the bottom whichever way the known books run.
      if (mine == null && theirs == null) {
        return b.importedAt.compareTo(a.importedAt);
      }

      // A book with no measurable progress sorts last under either
      // direction. It is not at zero percent; how far in it is is unknown,
      // and ADR 0013 is explicit that null and zero say different things.
      // Reversing to "least read first" would otherwise put every unopened
      // book above the one the reader has barely started, which reads as a
      // list of things they have read least and is a list of things nobody
      // knows about.
      if (mine == null) return 1;
      if (theirs == null) return -1;

      return flip * theirs.compareTo(mine);
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
    bool reversed = false,
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
        table.sourceFormat,
        table.updatedAt,
        positions.blockId,
        positions.charOffset,
        positions.parserVersion,
        positions.tokenIndex,
        positions.chapterTitle,
        positions.chapterEndIndex,
        positions.updatedAt,
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
          sourceFormat: row.read(table.sourceFormat)!,
          updatedAt: row.read(table.updatedAt),
          position: blockId == null
              ? null
              : Locator(
                  blockId: blockId,
                  charOffset: row.read(positions.charOffset)!,
                  parserVersion: row.read(positions.parserVersion)!,
                ),
          tokenIndex: row.read(positions.tokenIndex),
          chapterTitle: row.read(positions.chapterTitle),
          chapterEndIndex: row.read(positions.chapterEndIndex),
          lastReadAt: row.read(positions.updatedAt),
        );
      }).toList();

      books.sort((a, b) => _compare(sort, a, b, reversed: reversed));

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

  /// Stored bytes plus what a reopen needs beyond them.
  ///
  /// Replaced [bytesOf] once a note stopped carrying its own title: an
  /// EPUB's bytes are enough to reopen it, since the archive is where its
  /// title and id came from in the first place, but a note's bytes are just
  /// its text, and reopening it means feeding that text back in beside a
  /// title the bytes were never going to supply.
  Future<StoredBook?> storedBookOf(String bookId) async {
    final row = await (_db.select(
      _db.books,
    )..where((b) => b.id.equals(bookId))).getSingleOrNull();

    if (row == null) return null;

    return StoredBook(
      bytes: row.bytes,
      sourceFormat: row.sourceFormat,
      title: row.title,
      author: row.author,
    );
  }

  /// Adds a book, or replaces it if the same edition is imported again.
  ///
  /// Takes the parsed [book] and the [bytes] it was parsed from, rather than
  /// each field unpacked by hand: `id`, `title`, `author` and `language` come
  /// straight off [book], `wordCount` is `book.text.length`, and
  /// `sourceFormat` is `book.sourceFormat.name`. A caller that wants a
  /// different figure for one of these fixes the parse that produced [book]
  /// rather than restating the derivation at every import site.
  ///
  /// One transaction with the pending-position drain: a book that reached
  /// disk while its waiting position stayed behind would open at the start
  /// and then jump the moment the next sync ran.
  Future<void> addBook(LibraryBook book, Uint8List bytes) async {
    await _db.transaction(() async {
      await _db
          .into(_db.books)
          .insertOnConflictUpdate(
            BooksCompanion.insert(
              id: book.id,
              title: book.title,
              bytes: bytes,
              importedAt: DateTime.now().toUtc(),
              wordCount: Value(book.text.length),
              sourceFormat: Value(book.sourceFormat.name),
              author: Value(book.author),
              language: Value(book.language),
            ),
          );

      final coverBytes = book.coverBytes;
      if (coverBytes != null) {
        await _db
            .into(_db.bookCovers)
            .insertOnConflictUpdate(
              BookCoversCompanion.insert(bookId: book.id, bytes: coverBytes),
            );
      } else {
        // Re-importing an edition that no longer declares a cover should not
        // leave the old picture attached to the new book. A book with no
        // cover has no row.
        await (_db.delete(
          _db.bookCovers,
        )..where((c) => c.bookId.equals(book.id))).go();
      }

      await _drainPendingPosition(book.id);
    });
  }

  /// Rewrites a stored note's title and text.
  ///
  /// A plain update, not [addBook]'s `insertOnConflictUpdate`: that path
  /// rewrites `importedAt` to now on every call, which is right for
  /// re-importing an edition and wrong here — an edit changes when the note
  /// was last written, not when it first arrived.
  ///
  /// [resetProgress] is the caller's decision, not this method's: the editor
  /// screen is the one holding both the old and new text, so it is the one
  /// that can tell whether anything a reader was partway through actually
  /// changed. When true, the stored position is dropped in the same
  /// transaction as the rewrite, so a reader can never end up with a position
  /// pointing at a block a re-parse no longer produces.
  ///
  /// Not enqueued: book content has never synced, notes included, so there is
  /// nothing here for another device to receive.
  Future<void> editNote({
    required String id,
    required String title,
    required Uint8List bytes,
    required int wordCount,
    required bool resetProgress,
  }) async {
    await _db.transaction(() async {
      final now = DateTime.now().toUtc();

      await (_db.update(_db.books)..where((b) => b.id.equals(id))).write(
        BooksCompanion(
          title: Value(title),
          bytes: Value(bytes),
          wordCount: Value(wordCount),
          updatedAt: Value(now),
        ),
      );

      if (resetProgress) await _resetPosition(id);
    });
  }

  /// Drops a book's stored position, without touching the book itself.
  ///
  /// Assumes it is already inside a transaction.
  Future<void> _resetPosition(String bookId) async {
    await (_db.delete(
      _db.readingPositions,
    )..where((p) => p.bookId.equals(bookId))).go();

    // An unsent position event for the place just discarded would otherwise
    // go out on the next drain and write a locator back that this book no
    // longer resolves.
    await _coalescePositionEvents(bookId);
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
    String? chapterTitle,
    int? chapterEndIndex,
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
              // Same rule, and the same reason. The reader screen is the only
              // caller that knows a chapter, and it passes null whenever it
              // does not — in front matter, and for a book with no table of
              // contents. Leaving the column alone would keep the chapter the
              // reader was in an hour ago beside the place they are now.
              chapterTitle: Value(chapterTitle),
              chapterEndIndex: Value(chapterEndIndex),
              hlc: hlc,
              updatedAt: now,
            ),
          );

      await _coalescePositionEvents(bookId);

      // The chapter is deliberately absent from the payload. It describes
      // this device's parse of this copy of the book, so no other device
      // could act on one, and the wire contract is unchanged by ADR 0018.
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
              // Cleared, explicitly, rather than left to the conflict update
              // to skip. A remote position carries no chapter — nothing puts
              // one on the wire — so anything already in these columns
              // describes a place this reader has moved away from, on a
              // different device. insertOnConflictUpdate leaves columns the
              // companion omits untouched, which is precisely how a stale
              // title would survive beside a fresh locator.
              chapterTitle: const Value(null),
              chapterEndIndex: const Value(null),
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
              // A held position came off the wire and never had a chapter,
              // and the book it is about has only just been imported, so
              // nothing on this device has parsed it yet either.
              chapterTitle: const Value(null),
              chapterEndIndex: const Value(null),
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
  /// Resolves the one profile named rather than building the whole list.
  ///
  /// This used to call [allProfiles] and scan it, which reads every stored
  /// row and runs two `jsonDecode`s on each to find one. [watchActiveProfile]
  /// re-runs it on any write to either table it watches, and `preferences`
  /// takes a write from the sync engine three times a run, from the library
  /// whenever sort or the format filter changes, and from every appearance
  /// choice — so the cost landed on writes that have nothing to do with which
  /// profile is active.
  ///
  /// A preset does not touch the database at all. Presets are code (ADR
  /// 0008), so the `builtin.` namespace answers from [Presets.byId] without a
  /// query, which is the common case: it is what a reader who has never made
  /// a profile of their own is on.
  Future<ReadingProfile> activeProfile() async {
    final id = await preference(activeProfileKey);
    if (id == null) return Presets.standard;

    if (id.startsWith(ReadingProfile.builtInIdPrefix)) {
      // A pointer at a preset this build does not have is as dead as one at
      // a deleted row, and is cleared on the same reasoning.
      final preset = Presets.byId(id);
      if (preset != null) return preset;

      await _clearActiveProfile();
      return Presets.standard;
    }

    final row =
        await (_db.select(_db.storedProfiles)
              ..where((p) => p.id.equals(id) & p.deleted.equals(false)))
            .getSingleOrNull();

    if (row == null) {
      await _clearActiveProfile();
      return Presets.standard;
    }

    return _toProfile(row);
  }

  /// [activeProfile], re-read whenever the answer could have changed.
  ///
  /// The pointer is a preference and the profile it names is a row, so a
  /// stream over either one alone goes stale on the other: choosing a
  /// different profile writes the preference, and editing the active
  /// profile's pacing writes the row. The join is here for the tables it
  /// names rather than for the columns it selects — drift invalidates a
  /// query stream when any table it reads is written — and the row itself
  /// is discarded, because a built-in preset has no row to return.
  ///
  /// Emits on any write to either table rather than only on a change to
  /// this profile, because a filter would need an equality [ReadingProfile]
  /// does not define. That makes what each emission costs the thing worth
  /// keeping small, which is why [activeProfile] resolves one row by id
  /// instead of reading and decoding every profile the reader has.
  Stream<ReadingProfile> watchActiveProfile() {
    final pointer = _db.select(_db.preferences)
      ..where((p) => p.key.equals(activeProfileKey));

    final query = pointer.join([
      leftOuterJoin(
        _db.storedProfiles,
        _db.storedProfiles.id.equalsExp(_db.preferences.value),
        useColumns: false,
      ),
    ]);

    return query.watch().asyncMap((_) => activeProfile());
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
