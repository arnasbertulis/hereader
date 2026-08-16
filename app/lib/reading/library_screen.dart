import 'dart:async';
import 'dart:typed_data';

import 'package:epub_reader/epub_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../sync/api_client.dart';
import '../sync/sign_in_screen.dart';
import '../sync/sync_engine.dart';
import '../theme/app_tokens.dart';
import 'book_cover.dart';
import 'book_opener.dart';
import 'library_book.dart';
import 'paste_reader_screen.dart';

/// Where the sort the reader chose is remembered. Device-local, like every
/// other `ui.` key: which order a phone shows a shelf in is not a fact about
/// the account.
const _sortKey = 'ui.library_sort';

/// Width a tile aims for before the column count is worked out.
const double _targetTileWidth = 172;

/// Unscaled height of everything under a cover: two lines of title, one of
/// author, the progress row, and the gaps between them. Scaled with the
/// reader's text size to give the tile its height, since a fixed aspect ratio
/// clips the moment text grows.
const double _textBlockHeight = 96;

class LibraryScreen extends StatefulWidget {
  final LibraryRepository repository;
  final SyncEngine sync;
  final ApiClient api;

  /// Stamps the sort preference. Taken as a function rather than reached
  /// through [sync], so a widget test can supply one without standing up a
  /// clock, an auth store and a device id it has no use for.
  final Future<String> Function() issueStamp;

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.sync,
    required this.api,
    required this.issueStamp,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _busy = false;
  LibrarySort _sort = LibrarySort.recentlyAdded;

  /// The one path into the reader. Home's continue card takes the same
  /// object rather than its own copy of the sequence.
  late final BookOpener _opener;

  /// One future per book, kept so a rebuild does not re-read the blob.
  /// `FutureBuilder` restarts whenever it is handed a new future, and a grid
  /// hands its tiles new widgets on every scroll, resize and text-scale
  /// change.
  final _covers = <String, Future<Uint8List?>>{};

  LibraryRepository get _repo => widget.repository;

  @override
  void initState() {
    super.initState();
    _opener = BookOpener(repository: widget.repository, sync: widget.sync);
    unawaited(_restoreSort());
  }

  Future<void> _restoreSort() async {
    final stored = await _repo.preference(_sortKey);
    if (!mounted) return;

    setState(() => _sort = LibrarySort.byName(stored));
  }

  Future<void> _chooseSort(LibrarySort sort) async {
    setState(() => _sort = sort);

    await _repo.setPreference(
      _sortKey,
      sort.name,
      hlc: await widget.issueStamp(),
    );
  }

  Future<Uint8List?> _coverOf(String bookId) =>
      _covers.putIfAbsent(bookId, () => _repo.coverOf(bookId));

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
        coverBytes: book.coverBytes,
      );

      // Re-importing an id already in the library replaces its cover, and a
      // memoized future would keep handing out the old one. Cheaper to drop
      // every entry on an import than to work out which id changed.
      _covers.clear();
    } on EpubException catch (e) {
      _report(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows the library's busy state around the shared open path.
  ///
  /// The screen keeps the flag because it decides what busy looks like here:
  /// a bar under the app bar while the grid stays where it is.
  Future<void> _open(BookSummary summary) async {
    setState(() => _busy = true);

    try {
      await _opener.open(context, summary.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SignInScreen(api: widget.api)),
    );

    if (signedIn == true) unawaited(widget.sync.syncNow());
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

    if (confirmed == true) {
      unawaited(_covers.remove(summary.id));
      await _repo.removeBook(summary.id);
    }
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
        // A bar rather than a spinner over the whole body. Blanking the
        // library to say a book is opening throws away the thing the reader
        // was looking at to report on the thing they just tapped.
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  semanticsLabel: 'Working',
                ),
              )
            : null,
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
        ],
      ),
      body: StreamBuilder<List<BookSummary>>(
        stream: _repo.watchLibrary(sort: _sort),
        builder: (context, snapshot) {
          final books = snapshot.data;
          if (books == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (books.isEmpty) {
            return _EmptyLibrary(onImport: _busy ? null : _import);
          }

          return Column(
            children: [
              _LibraryHeader(
                count: books.length,
                sort: _sort,
                onSort: _busy ? null : _chooseSort,
              ),
              Expanded(
                child: RefreshIndicator(
                  // Pull to sync: the periodic timer is five minutes, which
                  // is a long time to wait when you have just put down
                  // another device.
                  onRefresh: widget.sync.syncNow,
                  child: _BookShelf(
                    books: books,
                    coverOf: _coverOf,
                    onOpen: _busy ? null : _open,
                    onRemove: _confirmRemove,
                  ),
                ),
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

/// How many books there are, and the order they are in.
class _LibraryHeader extends StatelessWidget {
  final int count;
  final LibrarySort sort;
  final ValueChanged<LibrarySort>? onSort;

  const _LibraryHeader({
    required this.count,
    required this.sort,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _screenPadding(context),
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == 1 ? '1 book' : '$count books',
              style: theme.textTheme.titleMedium,
            ),
          ),
          PopupMenuButton<LibrarySort>(
            enabled: onSort != null,
            tooltip: 'Change the order',
            initialValue: sort,
            onSelected: onSort,
            itemBuilder: (context) => [
              for (final option in LibrarySort.values)
                PopupMenuItem(value: option, child: Text(option.label)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(sort.label, style: theme.textTheme.labelLarge),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The books themselves, as a grid or as a single column of rows.
///
/// One column is not a narrow grid. A cover stretched across a phone at 200%
/// text scale is a card the reader scrolls past one book at a time, so below
/// two columns the tile turns on its side and the cover shrinks to a thumbnail
/// beside the text.
class _BookShelf extends StatelessWidget {
  final List<BookSummary> books;
  final Future<Uint8List?> Function(String bookId) coverOf;
  final ValueChanged<BookSummary>? onOpen;
  final ValueChanged<BookSummary> onRemove;

  const _BookShelf({
    required this.books,
    required this.coverOf,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final padding = _screenPadding(context);
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - padding * 2;
        var columns =
            ((available + AppSpacing.md) / (_targetTileWidth + AppSpacing.md))
                .floor();

        // Large text needs a wider tile for the same number of words, so a
        // column comes off before anything has to ellipsize. The threshold is
        // in scaled pixels rather than in a scale factor, because that is
        // what actually decides whether a title fits.
        if (scaler.scale(14) > 18) columns -= 1;
        columns = columns.clamp(1, 4);

        if (columns == 1) {
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(padding, 0, padding, AppSpacing.xxl),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: books.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, i) => _BookRow(
              book: books[i],
              cover: coverOf(books[i].id),
              onOpen: onOpen,
              onRemove: onRemove,
            ),
          );
        }

        final tileWidth = (available - AppSpacing.md * (columns - 1)) / columns;

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(padding, 0, padding, AppSpacing.xxl),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.lg,
            // Computed rather than an aspect ratio. A ratio fixes the text
            // block to a fraction of the cover, so the first reader to raise
            // their text size loses the author line to a clip.
            mainAxisExtent:
                tileWidth * kCoverAspect + scaler.scale(_textBlockHeight),
          ),
          itemCount: books.length,
          itemBuilder: (context, i) => _BookTile(
            book: books[i],
            cover: coverOf(books[i].id),
            width: tileWidth,
            onOpen: onOpen,
            onRemove: onRemove,
          ),
        );
      },
    );
  }
}

/// What the reader is told about their place in a book.
///
/// Three answers, not one bar drawn three ways. A book at zero percent and a
/// book whose progress is unknown look identical as an empty bar, and only
/// one of them is a fact.
({String label, double? value}) _progressOf(BookSummary book) {
  final progress = book.progress;

  if (progress != null) {
    return (label: '${_percent(progress)}%', value: progress);
  }
  if (book.started) return (label: 'In progress', value: null);

  return (label: 'Not started', value: null);
}

int _percent(double progress) => (progress * 100).round();

/// What a screen reader says for a tile.
String _semanticsFor(BookSummary book) {
  final progress = book.progress;

  final String place;
  if (progress != null) {
    place = '${_percent(progress)} percent read';
  } else if (book.started) {
    place = 'in progress';
  } else {
    place = 'not started';
  }

  return <String>[book.title, ?book.author, place].join(', ');
}

/// A book in the grid: cover, title, author, place.
class _BookTile extends StatelessWidget {
  final BookSummary book;
  final Future<Uint8List?> cover;
  final double width;
  final ValueChanged<BookSummary>? onOpen;
  final ValueChanged<BookSummary> onRemove;

  const _BookTile({
    required this.book,
    required this.cover,
    required this.width,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        // One node for the whole tile. Read out cover, title, author and
        // percentage separately it is four stops to learn one book.
        Semantics(
          button: true,
          label: _semanticsFor(book),
          excludeSemantics: true,
          child: InkWell(
            onTap: onOpen == null ? null : () => onOpen!(book),
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Cover(book: book, cover: cover, width: width),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                if (book.author != null)
                  Text(
                    book.author!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                _ProgressLine(book: book),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: _TileMenu(book: book, onRemove: onRemove),
        ),
      ],
    );
  }
}

/// A book in the single-column layout: thumbnail beside the text.
class _BookRow extends StatelessWidget {
  final BookSummary book;
  final Future<Uint8List?> cover;
  final ValueChanged<BookSummary>? onOpen;
  final ValueChanged<BookSummary> onRemove;

  const _BookRow({
    required this.book,
    required this.cover,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: _semanticsFor(book),
            excludeSemantics: true,
            child: InkWell(
              onTap: onOpen == null ? null : () => onOpen!(book),
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Cover(book: book, cover: cover, width: 72),
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
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: AppSpacing.sm),
                        _ProgressLine(book: book),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _TileMenu(book: book, onRemove: onRemove),
      ],
    );
  }
}

/// The cover, once its bytes have been read.
class _Cover extends StatelessWidget {
  final BookSummary book;
  final Future<Uint8List?> cover;
  final double width;

  const _Cover({required this.book, required this.cover, required this.width});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: cover,
      builder: (context, snapshot) => BookCoverImage(
        bookId: book.id,
        title: book.title,
        width: width,
        // Null while the read is in flight, which draws the generated face
        // and then replaces it. No spinner: a blob read off a local database
        // finishes inside a frame or two, and a spinner per tile would be
        // more motion than the thing it is reporting on.
        bytes: snapshot.data,
      ),
    );
  }
}

/// The bar and the percentage, or the words that stand in for them.
class _ProgressLine extends StatelessWidget {
  final BookSummary book;

  const _ProgressLine({required this.book});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _progressOf(book);

    final label = Text(
      progress.label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        // Percentages that change as the reader moves should not shift the
        // text beside them.
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    if (progress.value == null) return label;

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: LinearProgressIndicator(value: progress.value, minHeight: 4),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        label,
      ],
    );
  }
}

/// Actions that are not opening the book.
///
/// Behind a menu rather than beside the title, because the only one of them
/// is destructive and a mis-tap on a shelf should not start a removal.
class _TileMenu extends StatelessWidget {
  final BookSummary book;
  final ValueChanged<BookSummary> onRemove;

  const _TileMenu({required this.book, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopupMenuButton<String>(
      tooltip: 'More for ${book.title}',
      // A named value rather than a nullable one: PopupMenuButton reads a
      // null result as a dismissal and never calls onSelected.
      onSelected: (_) => onRemove(book),
      itemBuilder: (context) => const [
        PopupMenuItem<String>(value: 'remove', child: Text('Remove')),
      ],
      icon: DecoratedBox(
        // The icon sits over a cover it knows nothing about, so it carries
        // its own background rather than trusting the image behind it.
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surface.withValues(alpha: 0.85),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Icon(Icons.more_vert, size: 20, color: scheme.onSurface),
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

class _EmptyLibrary extends StatelessWidget {
  final VoidCallback? onImport;

  const _EmptyLibrary({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No books yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add an EPUB to start reading. Books stay on this device.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
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
