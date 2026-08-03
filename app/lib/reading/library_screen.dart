import 'package:epub_reader/epub_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../sync/api_client.dart';
import '../sync/sign_in_screen.dart';
import '../sync/sync_engine.dart';
import 'library_book.dart';
import 'paste_reader_screen.dart';
import 'reader_screen.dart';

class LibraryScreen extends StatefulWidget {
  final LibraryRepository repository;
  final SyncEngine sync;
  final ApiClient api;

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.sync,
    required this.api,
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
      final bytes = await _repo.bytesOf(summary.id);
      if (bytes == null) {
        _report('That book is not on this device.');
        return;
      }

      // Re-parsed rather than cached: the parser is the single source of
      // truth for block ids and offsets, so a normalizer change applies to
      // books already in the library instead of invalidating them.
      final parsed = await const BookImporter().import(bytes);
      final book = parsed.withPosition(summary.position);

      if (!mounted) return;

      final result = await Navigator.of(context).push<ReadingResult>(
        MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
      );

      if (result == null) return;

      await _repo.savePosition(
        bookId: summary.id,
        locator: result.locator,
        // A real clock stamp, not a wall-clock string: the service rejects
        // anything that does not parse, and ordering across devices depends
        // on this being monotonic.
        hlc: await widget.sync.issueStamp(),
        // The service has no copy of the book, so it cannot tell how far
        // apart two positions are without this hint.
        tokenIndex: result.tokenIndex,
      );

      // Positions are worth sending promptly: the reader may pick up
      // another device in a minute.
      widget.sync.syncNow();
    } on EpubException catch (e) {
      _report(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SignInScreen(api: widget.api)),
    );

    if (signedIn == true) widget.sync.syncNow();
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
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PasteReaderScreen(),
                    ),
                  ),
            icon: const Icon(Icons.content_paste),
            tooltip: 'Read pasted text',
          ),
          IconButton(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.add),
            tooltip: 'Add a book',
          ),
        ],
      ),
      body: StreamBuilder<List<BookSummary>>(
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
              child: CircularProgressIndicator(strokeWidth: 2),
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
