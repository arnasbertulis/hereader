import 'dart:async';

import 'package:epub_reader/epub_reader.dart';
import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../sync/sync_engine.dart';
import 'library_book.dart';
import 'reader_screen.dart';

/// Carries a reader from a book id into the reader screen.
///
/// This is not a navigation call. It syncs first, settles a divergence if one
/// is waiting, reads the stored bytes, re-parses them, re-reads the position
/// that sync may have just changed, and pushes the reader with a save
/// callback that runs for the whole sitting.
///
/// It lives outside [State] because more than one screen opens books. The
/// library list opens them today and Home's continue card opens them next,
/// and a second copy of this sequence would skip the conflict prompt without
/// anything failing. ADR 0011 names that shape: two paths writing one fact is
/// how they come apart.
///
/// Holds no state and no [BuildContext]. Each call takes the context of the
/// widget that started it, so the object can sit in a [State] field for the
/// life of a screen while the context it uses stays scoped to one call.
class BookOpener {
  final LibraryRepository repository;
  final SyncEngine sync;

  const BookOpener({required this.repository, required this.sync});

  /// Opens [bookId], reporting anything that stops it through [context].
  ///
  /// Returns when the reader closes the book. The caller owns whatever busy
  /// affordance it shows meanwhile: the library blanks its list, and Home
  /// wants something smaller than that.
  Future<void> open(BuildContext context, String bookId) async {
    try {
      // Sync before opening rather than only checking: a divergence may
      // exist that this device has not heard about yet, and reading from a
      // stale position before discovering it is the failure this whole
      // design exists to avoid. Offline is fine — syncNow reports and
      // returns rather than throwing, so reading never depends on a network.
      await sync.syncNow();

      final conflicts = await repository.watchConflicts().first;

      if (conflicts.any((c) => c.bookId == bookId)) {
        // The watcher is already showing the sheet. Wait for the answer
        // rather than sending the reader back to tap again, which would
        // repeat the sync that just ran.
        final settled = await _waitForConflict(bookId);
        if (!context.mounted) return;

        if (!settled) {
          // Resolving failed, most likely because the network dropped
          // mid-choice. Better to say so than to hold the reader in a
          // spinner indefinitely.
          _report(context, 'Could not settle where to carry on. Try again.');
          return;
        }
      }

      final stored = await repository.storedBookOf(bookId);
      if (!context.mounted) return;

      if (stored == null) {
        _report(context, 'That book is not on this device.');
        return;
      }

      // Re-parsed rather than cached: the parser is the single source of
      // truth for block ids and offsets, so a normalizer change applies to
      // books already in the library instead of invalidating them.
      final parsed = await const BookParser().reopenStored(
        stored.bytes,
        sourceFormat: BookSourceFormat.fromName(stored.sourceFormat),
        id: bookId,
        title: stored.title,
      );

      // Read fresh rather than trusting a summary captured when the list was
      // last built. A conflict settled moments ago would otherwise be
      // ignored and the reader sent to the old position.
      final position = await repository.positionOf(bookId);
      if (!context.mounted) return;

      final book = parsed.withPosition(position);

      if (book.positionUnresolvable) {
        // Silently restarting looks identical to losing the reader's place.
        _report(
          context,
          'Your saved place in this book could not be found, so it opens '
          'from the start.',
        );
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            book: book,
            // The reader needs these to list the profiles actually on this
            // device and to remember which one was picked.
            repository: repository,
            issueStamp: sync.issueStamp,
            // The screen decides when a place is worth recording — ADR 0011
            // — and this decides how. It is called throughout the session
            // now, not once at the end.
            onSave: (result) => _savePosition(bookId, result),
          ),
        ),
      );

      // Positions are worth sending promptly: the reader may pick up
      // another device in a minute. Everything written while the book was
      // open is already queued, coalesced down to the latest.
      unawaited(sync.syncNow());
    } on EpubException catch (e) {
      if (context.mounted) _report(context, e.message);
    }
  }

  /// Writes a place the reader has reached.
  ///
  /// Called many times per sitting rather than once at the end. The
  /// repository drops any queued event for the same book that has never been
  /// sent, so the extra writes cost nothing on the wire.
  Future<void> _savePosition(String bookId, ReadingResult result) async {
    await repository.savePosition(
      bookId: bookId,
      locator: result.locator,
      // A real clock stamp, not a wall-clock string: the service rejects
      // anything that does not parse, and ordering across devices depends
      // on this being monotonic.
      hlc: await sync.issueStamp(),
      // The service has no copy of the book, so it cannot work out how far
      // apart two positions are without this hint.
      tokenIndex: result.tokenIndex,
      // These two go no further than the database. They let Home and the
      // library say which chapter the reader is in without parsing a book to
      // draw a tile. See ADR 0018.
      chapterTitle: result.chapterTitle,
      chapterEndIndex: result.chapterEndIndex,
    );
  }

  /// Waits for the reader to settle a divergence on [bookId].
  ///
  /// Bounded, because the sheet cannot be dismissed: if resolving fails the
  /// reader would otherwise be held in a spinner with no way out.
  Future<bool> _waitForConflict(String bookId) async {
    try {
      await repository
          .watchConflicts()
          .firstWhere((list) => !list.any((c) => c.bookId == bookId))
          .timeout(const Duration(minutes: 2));
      return true;
    } on TimeoutException {
      return false;
    }
  }

  void _report(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
