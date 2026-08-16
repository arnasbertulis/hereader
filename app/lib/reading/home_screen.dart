import 'dart:async';
import 'dart:typed_data';

import 'package:epub_reader/epub_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../sync/api_client.dart';
import '../sync/sign_in_screen.dart';
import '../sync/sync_button.dart';
import '../sync/sync_engine.dart';
import '../theme/app_tokens.dart';
import 'book_cover.dart';
import 'book_opener.dart';
import 'book_progress.dart';
import 'paste_reader_screen.dart';

/// How many books the recent row shows, beyond the one in the continue card.
const int _recentCount = 6;

/// Cover width in the recent row. Narrower than a library tile: this row
/// exists to get the reader back into a book they were in, not to browse.
const double _recentCoverWidth = 96;

/// Unscaled height of the title line under a recent cover, plus its gap.
/// Scaled with the reader's text size, since a fixed row height clips the
/// moment text grows.
const double _recentTextHeight = 44;

/// The first screen, and the one that answers "where was I".
///
/// Ordered by when a book was last read rather than when it arrived. Those
/// are different questions and the library already answers the other one:
/// a book imported this morning and never opened does not belong above the
/// one the reader was in last night.
class HomeScreen extends StatefulWidget {
  final LibraryRepository repository;
  final SyncEngine sync;
  final ApiClient api;

  /// Stamps anything the paste screen writes. Taken as a function rather
  /// than reached through [sync], so a widget test can supply one without
  /// standing up a clock, an auth store and a device id it has no use for.
  final Future<String> Function() issueStamp;

  const HomeScreen({
    super.key,
    required this.repository,
    required this.sync,
    required this.api,
    required this.issueStamp,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;

  /// The same sequence the library runs, not a second copy of it. ADR 0011
  /// names the shape: two paths writing one fact is how they come apart.
  late final BookOpener _opener;

  /// One future per book, kept so a rebuild does not re-read the blob. Home
  /// draws at most seven covers, so this stays small without eviction.
  final _covers = <String, Future<Uint8List?>>{};

  LibraryRepository get _repo => widget.repository;

  @override
  void initState() {
    super.initState();
    _opener = BookOpener(repository: widget.repository, sync: widget.sync);
  }

  Future<Uint8List?> _coverOf(String bookId) =>
      _covers.putIfAbsent(bookId, () => _repo.coverOf(bookId));

  /// Opens a book, showing busy inside the continue card.
  ///
  /// Home keeps the flag rather than the opener, because Home's answer to
  /// busy is different from the library's: the card carries a spinner where
  /// its button was, and everything else on the screen stays put.
  Future<void> _open(BookSummary book) async {
    setState(() => _busy = true);

    try {
      await _opener.open(context, book.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
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
        coverBytes: book.coverBytes,
      );

      _covers.clear();
    } on EpubException catch (e) {
      _report(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openPaste() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PasteReaderScreen(
          repository: _repo,
          issueStamp: widget.issueStamp,
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SignInScreen(api: widget.api)),
    );

    if (signedIn == true) unawaited(widget.sync.syncNow());

    // The account strip reads `isSignedIn` directly rather than a stream, so
    // it needs telling that the answer changed.
    if (mounted) setState(() {});
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
        title: const Text('hereader'),
        actions: [
          SyncButton(sync: widget.sync, api: widget.api, onSignIn: _signIn),
        ],
      ),
      body: StreamBuilder<List<BookSummary>>(
        stream: _repo.watchLibrary(),
        builder: (context, snapshot) {
          final books = snapshot.data;
          if (books == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final recent = byLastRead(books);

          return ListView(
            padding: EdgeInsets.symmetric(
              horizontal: _screenPadding(context),
              vertical: AppSpacing.lg,
            ),
            children: [
              if (recent.isEmpty)
                _NothingOpenYet(
                  onImport: _busy ? null : _import,
                  onPaste: _busy ? null : _openPaste,
                )
              else ...[
                const _SectionLabel('Continue reading'),
                const SizedBox(height: AppSpacing.sm),
                _ContinueCard(
                  book: recent.first,
                  cover: _coverOf(recent.first.id),
                  busy: _busy,
                  onOpen: _busy ? null : _open,
                ),
                // Between here and Recent sits the stats strip section 7.1
                // reserves. Nothing renders there until there are stats
                // worth reading; a box explaining what will eventually
                // arrive is the placeholder that section rules out.
                if (recent.length > 1) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  const _SectionLabel('Recent'),
                  const SizedBox(height: AppSpacing.sm),
                  _RecentRow(
                    books: recent.skip(1).take(_recentCount).toList(),
                    coverOf: _coverOf,
                    onOpen: _busy ? null : _open,
                  ),
                ],
              ],
              const SizedBox(height: AppSpacing.xxl),
              _AccountStrip(
                signedIn: widget.api.auth.isSignedIn,
                onSignIn: _signIn,
                onSyncNow: widget.sync.syncNow,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Screen padding: 16 below 600dp, 24 from 600dp up.
double _screenPadding(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 600 ? AppSpacing.xl : AppSpacing.lg;

/// [books], most recently read first.
///
/// A book with no position row has never been opened and has no reading
/// date, so its import stands in. That puts a fresh import at the top until
/// something else is read, which is what a reader who just added a book
/// expects to see.
///
/// Sorted here rather than in SQL. The fallback is a choice between two
/// columns, one of them from an outer join, and the library already sorts
/// its own list in Dart for the same reason.
List<BookSummary> byLastRead(List<BookSummary> books) {
  final sorted = [...books];
  sorted.sort((a, b) => _activityOf(b).compareTo(_activityOf(a)));

  return sorted;
}

DateTime _activityOf(BookSummary book) => book.lastReadAt ?? book.importedAt;

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      header: true,
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The book the reader is in, with the way back into it.
///
/// The card itself does not take a tap. A card that opens the book with a
/// button on it that also opens the book gives one action two targets, and
/// the outer one swallows the reader's aim for the inner.
class _ContinueCard extends StatelessWidget {
  final BookSummary book;
  final Future<Uint8List?> cover;
  final bool busy;
  final ValueChanged<BookSummary>? onOpen;

  const _ContinueCard({
    required this.book,
    required this.cover,
    required this.busy,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hairline = theme.dividerTheme.thickness ?? AppHairline.width;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: scheme.outlineVariant, width: hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookCoverFuture(
            bookId: book.id,
            title: book.title,
            cover: cover,
            width: 72,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                if (book.author != null)
                  Text(
                    book.author!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                BookProgressLine(book: book),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: onOpen == null ? null : () => onOpen!(book),
                  child: busy
                      // The spinner sits inside the button rather than over
                      // the screen, so the thing that is working is the
                      // thing that was tapped.
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            semanticsLabel: 'Opening',
                          ),
                        )
                      : Text(book.started ? 'Continue' : 'Start reading'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The books under the continue card, most recently read first.
class _RecentRow extends StatelessWidget {
  final List<BookSummary> books;
  final Future<Uint8List?> Function(String bookId) coverOf;
  final ValueChanged<BookSummary>? onOpen;

  const _RecentRow({
    required this.books,
    required this.coverOf,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);

    return SizedBox(
      height:
          _recentCoverWidth * kCoverAspect + scaler.scale(_recentTextHeight),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: books.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, i) => _RecentTile(
          book: books[i],
          cover: coverOf(books[i].id),
          onOpen: onOpen,
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  final BookSummary book;
  final Future<Uint8List?> cover;
  final ValueChanged<BookSummary>? onOpen;

  const _RecentTile({
    required this.book,
    required this.cover,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: semanticsForBook(book),
      excludeSemantics: true,
      child: InkWell(
        onTap: onOpen == null ? null : () => onOpen!(book),
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: SizedBox(
          width: _recentCoverWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCoverFuture(
                bookId: book.id,
                title: book.title,
                cover: cover,
                width: _recentCoverWidth,
              ),
              const SizedBox(height: AppSpacing.xs),
              // One line, not two. The row scrolls sideways and a second
              // line of title on every tile costs the same height whether
              // the titles need it or not.
              Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What Home shows before there is anything to continue.
class _NothingOpenYet extends StatelessWidget {
  final VoidCallback? onImport;
  final VoidCallback? onPaste;

  const _NothingOpenYet({required this.onImport, required this.onPaste});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xxl),
        Text(
          'Nothing open yet',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Add a book to begin. Books stay on this device.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xl),
        Center(
          child: FilledButton.icon(
            onPressed: onImport,
            style: FilledButton.styleFrom(minimumSize: const Size(200, 56)),
            icon: const Icon(Icons.add),
            label: const Text('Add a book'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: TextButton.icon(
            onPressed: onPaste,
            style: TextButton.styleFrom(minimumSize: const Size(200, 48)),
            icon: const Icon(Icons.content_paste),
            label: const Text('Read pasted text'),
          ),
        ),
      ],
    );
  }
}

/// The invitation to sync, or the state of it once there is an account.
///
/// Signed out this is an invitation, not a gate: everything on this screen
/// works without an account, and the card says what an account adds rather
/// than what it unlocks.
///
/// Signed in it reports and offers a manual run. No last-synced time yet:
/// `SyncState` carries a status and a message, not a timestamp, and a time
/// invented on this screen from when the status last changed would be a
/// different fact wearing the same words.
class _AccountStrip extends StatelessWidget {
  final bool signedIn;
  final VoidCallback onSignIn;
  final Future<void> Function() onSyncNow;

  const _AccountStrip({
    required this.signedIn,
    required this.onSignIn,
    required this.onSyncNow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hairline = theme.dividerTheme.thickness ?? AppHairline.width;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: scheme.outlineVariant, width: hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              signedIn
                  ? 'Your place syncs across your devices.'
                  : 'Sign in to sync your place across devices.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (signedIn)
            TextButton(
              onPressed: () => unawaited(onSyncNow()),
              child: const Text('Sync now'),
            )
          else
            FilledButton.tonal(
              onPressed: onSignIn,
              child: const Text('Sign in'),
            ),
        ],
      ),
    );
  }
}
