import 'dart:async';

import 'package:epub_reader/epub_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../sync/api_client.dart';
import '../sync/sign_in_screen.dart';
import '../sync/sync_engine.dart';
import '../theme/appearance.dart';
import 'library_book.dart';
import 'paste_reader_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends StatefulWidget {
  final LibraryRepository repository;
  final SyncEngine sync;
  final ApiClient api;

  /// Passed through to the settings screen, which is where appearance is
  /// changed until the navigation shell gives settings a tab of its own.
  final AppearanceController appearance;

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.sync,
    required this.api,
    required this.appearance,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _busy = false;

  LibraryRepository get _repo => widget.repository;

  Future<void> _import() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
      // Bytes rather than a path: the web has no file behind the dialog, and
      // the bytes are what gets stored anyway.
      withData: true,
    );

    final bytes = result?.files.singleOrNull?.bytes;
    if (bytes == null || !mounted) return;

    setState(() => _busy = true);

    try {
      final book = await const BookImporter().import(bytes);

      await _repo.addBook(
        id: book.id,
        title: book.title,
        author: book.author,
        language: book.language,
        bytes: bytes,
        wordCount: book.text.length,
      );
    } on EpubException catch (e) {
      _report(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(BookSummary summary) async {
    setState(() => _busy = true);

    try {
      // Sync before opening rather than only checking: a divergence may
      // exist that this device has not heard about yet, and reading from a
      // stale position before discovering it is the failure this whole
      // design exists to avoid. Offline is fine — syncNow reports and
      // returns rather than throwing, so reading never depends on a network.
      await widget.sync.syncNow();

      final conflicts = await _repo.watchConflicts().first;

      if (conflicts.any((c) => c.bookId == summary.id)) {
        // The watcher is already showing the sheet. Wait for the answer
        // rather than sending the reader back to tap again, which would
        // repeat the sync that just ran.
        final settled = await _waitForConflict(summary.id);

        if (!settled) {
          // Resolving failed, most likely because the network dropped
          // mid-choice. Better to say so than to hold the reader in a
          // spinner indefinitely.
          _report('Could not settle where to carry on. Try again.');
          return;
        }
        if (!mounted) return;
      }

      final bytes = await _repo.bytesOf(summary.id);
      if (bytes == null) {
        _report('That book is not on this device.');
        return;
      }

      // Re-parsed rather than cached: the parser is the single source of
      // truth for block ids and offsets, so a normalizer change applies to
      // books already in the library instead of invalidating them.
      final parsed = await const BookImporter().import(bytes);

      // Read fresh rather than trusting the summary, which was captured
      // when the list was last built. A conflict settled moments ago would
      // otherwise be ignored and the reader sent to the old position.
      final stored = await _repo.positionOf(summary.id);
      final book = parsed.withPosition(stored);

      if (book.positionUnresolvable) {
        // Silently restarting looks identical to losing the reader's place.
        _report(
          'Your saved place in this book could not be found, so it opens '
          'from the start.',
        );
      }

      if (!mounted) return;

      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            book: book,
            // The reader needs these to list the profiles actually on this
            // device and to remember which one was picked.
            repository: _repo,
            issueStamp: widget.sync.issueStamp,
            // The screen decides when a place is worth recording — ADR 0011
            // — and this decides how. It is called throughout the session
            // now, not once at the end.
            onSave: (result) => _savePosition(summary.id, result),
          ),
        ),
      );

      // Positions are worth sending promptly: the reader may pick up
      // another device in a minute. Everything written while the book was
      // open is already queued, coalesced down to the latest.
      unawaited(widget.sync.syncNow());
    } on EpubException catch (e) {
      _report(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Writes a place the reader has reached.
  ///
  /// Called many times per sitting rather than once at the end. The
  /// repository drops any queued event for the same book that has never been
  /// sent, so the extra writes cost nothing on the wire.
  Future<void> _savePosition(String bookId, ReadingResult result) async {
    await _repo.savePosition(
      bookId: bookId,
      locator: result.locator,
      // A real clock stamp, not a wall-clock string: the service rejects
      // anything that does not parse, and ordering across devices depends
      // on this being monotonic.
      hlc: await widget.sync.issueStamp(),
      // The service has no copy of the book, so it cannot work out how far
      // apart two positions are without this hint.
      tokenIndex: result.tokenIndex,
    );
  }

  /// Waits for the reader to settle a divergence on [bookId].
  ///
  /// Bounded, because the sheet cannot be dismissed: if resolving fails the
  /// reader would otherwise be held in a spinner with no way out.
  Future<bool> _waitForConflict(String bookId) async {
    try {
      await _repo
          .watchConflicts()
          .firstWhere((list) => !list.any((c) => c.bookId == bookId))
          .timeout(const Duration(minutes: 2));
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> _signIn() async {
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SignInScreen(api: widget.api)),
    );

    if (signedIn == true) unawaited(widget.sync.syncNow());
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          repository: _repo,
          issueStamp: widget.sync.issueStamp,
          appearance: widget.appearance,
        ),
      ),
    );
  }

  void _openPaste() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PasteReaderScreen(
          repository: _repo,
          issueStamp: widget.sync.issueStamp,
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BookSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${summary.title}?'),
        content: const Text(
          'The file and your place in it are deleted from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) await _repo.removeBook(summary.id);
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          _SyncButton(sync: widget.sync, api: widget.api, onSignIn: _signIn),
          IconButton(
            onPressed: _busy ? null : _openPaste,
            icon: const Icon(Icons.content_paste),
            tooltip: 'Read pasted text',
          ),
          IconButton(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.add),
            tooltip: 'Add a book',
          ),
          IconButton(
            onPressed: _busy ? null : _openSettings,
            icon: const Icon(Icons.tune),
            tooltip: 'Reading profiles',
          ),
        ],
      ),
      body: RefreshIndicator(
        // Pull to sync: the periodic timer is five minutes, which is a long
        // time to wait when you have just put down another device.
        onRefresh: widget.sync.syncNow,
        child: StreamBuilder<List<BookSummary>>(
          stream: _repo.watchLibrary(),
          builder: (context, snapshot) {
            if (_busy) {
              return const Center(child: CircularProgressIndicator());
            }

            final books = snapshot.data;
            if (books == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (books.isEmpty) {
              return _EmptyLibrary(onImport: _import);
            }

            return ListView.separated(
              itemCount: books.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _BookTile(
                book: books[i],
                onTap: () => _open(books[i]),
                onRemove: () => _confirmRemove(books[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Sync state in the app bar, and the way in to signing in.
///
/// Deliberately quiet. Sync failing is not the reader's problem to solve
/// mid-chapter, so nothing here interrupts; it reports and gets out of the
/// way.
class _SyncButton extends StatelessWidget {
  final SyncEngine sync;
  final ApiClient api;
  final VoidCallback onSignIn;

  const _SyncButton({
    required this.sync,
    required this.api,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncState>(
      stream: sync.state,
      builder: (context, snapshot) {
        if (!api.auth.isSignedIn) {
          return IconButton(
            onPressed: onSignIn,
            icon: const Icon(Icons.cloud_off_outlined),
            tooltip: 'Sign in to sync',
          );
        }

        final status = snapshot.data?.status ?? SyncStatus.idle;

        return switch (status) {
          SyncStatus.syncing => const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                // Every other arm of this switch is a button with a
                // tooltip. This one replaces the button while a sync runs,
                // so without a label the control disappears from the
                // semantics tree entirely rather than changing state.
                semanticsLabel: 'Syncing',
              ),
            ),
          ),
          SyncStatus.offline => IconButton(
            onPressed: sync.syncNow,
            icon: const Icon(Icons.cloud_off),
            tooltip: 'Offline. Changes are saved and will sync later.',
          ),
          SyncStatus.failed => IconButton(
            onPressed: sync.syncNow,
            icon: Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            tooltip: snapshot.data?.message ?? 'Sync failed. Tap to retry.',
          ),
          _ => IconButton(
            onPressed: sync.syncNow,
            icon: const Icon(Icons.cloud_done_outlined),
            tooltip: 'Synced. Tap to sync now.',
          ),
        };
      },
    );
  }
}

class _BookTile extends StatelessWidget {
  final BookSummary book;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _BookTile({
    required this.book,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final started = book.position != null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(book.title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (book.author != null) Text(book.author!),
          const SizedBox(height: 6),
          Text(
            started ? 'In progress' : '${book.wordCount} words',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(started ? Icons.play_arrow : Icons.chevron_right),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove',
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final VoidCallback onImport;

  const _EmptyLibrary({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No books yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Add an EPUB to start reading. Books stay on this device.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onImport,
              style: FilledButton.styleFrom(minimumSize: const Size(200, 56)),
              icon: const Icon(Icons.add),
              label: const Text('Add a book'),
            ),
          ],
        ),
      ),
    );
  }
}
