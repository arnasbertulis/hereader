import 'dart:async';
import 'dart:typed_data';

import 'package:epub_reader/epub_reader.dart';
import 'package:flutter/material.dart';

import '../catalogue/catalogue_client.dart';
import '../catalogue/catalogue_importer.dart';
import '../data/library_repository.dart';
import '../net/http_transport.dart';
import '../sync/sync_engine.dart';
import '../theme/app_tokens.dart';
import 'book_cover.dart';
import 'book_opener.dart';
import 'library_book.dart';

/// Identifies the search field for tests, which have no button label to
/// match against — the field carries no text of its own until the reader
/// types into it.
const Key freeBooksSearchFieldKey = Key('free-books-search-field');

/// Identifies the grid of results.
const Key freeBooksGridKey = Key('free-books-grid');

/// Identifies the full-screen spinner shown while the first page loads.
const Key freeBooksLoadingKey = Key('free-books-loading');

/// Identifies the thin bar shown while a further page loads under an
/// already-visible grid.
const Key freeBooksLoadingMoreKey = Key('free-books-loading-more');

/// Identifies the empty/error message, whichever of the three it is holding.
const Key freeBooksMessageKey = Key('free-books-message');

/// Identifies the button that repeats the last search.
const Key freeBooksRetryButtonKey = Key('free-books-retry-button');

/// One tile's key, so a test can find a specific book by id rather than by
/// the title it happens to carry this week.
Key freeBooksTileKey(int gutenbergId) => Key('free-books-tile-$gutenbergId');

/// How long a keystroke waits before it becomes a search.
///
/// Short enough that the list still feels live, long enough that a reader
/// typing a whole word does not fire one request per letter.
const _debounceDelay = Duration(milliseconds: 400);

/// How close to the bottom the grid has to scroll before the next page is
/// asked for, in logical pixels.
const double _loadMoreThreshold = 300;

/// Height of a tile's text block: two lines of title, one of author, one of
/// status. Shorter than the Library shelf's own text block, because a
/// Catalogue tile carries no place or progress line — there is nothing to
/// resume in a book not yet on this device.
const double _textBlockHeight = 96;

enum _FreeBooksProblem {
  /// The search or listing ran and matched nothing.
  nothingMatched,

  /// The device could not reach the server at all.
  noConnection,

  /// The server answered, but the Catalogue itself is not ready — ADR 0029:
  /// ingestion can be mid-run or have never completed.
  catalogueUnavailable,
}

/// Browsing and importing from the Gutenberg Catalogue.
///
/// A full-screen route rather than a sheet: the grid, the search field and
/// the infinite scroll all want the room a sheet would have to fight the nav
/// bar for. Pushed the same way the library's own EPUB picker and paste
/// screen are, so the three destinations in [AppShell]'s bar never grow a
/// fourth.
///
/// Search debounces; opening the screen with nothing typed shows the most
/// downloaded books, which is the one useful default a reader who has never
/// heard of a specific title still has.
class FreeBooksScreen extends StatefulWidget {
  final CatalogueClient client;
  final LibraryRepository repository;
  final SyncEngine sync;

  /// Parses a download into a [LibraryBook]. Overridable so a test can stand
  /// in for it: the default runs a real parse through `compute()`, which
  /// spawns an isolate a widget test has no way to wait on cheaply.
  final BookImporter bookImporter;

  const FreeBooksScreen({
    super.key,
    required this.client,
    required this.repository,
    required this.sync,
    this.bookImporter = const BookImporter(),
  });

  @override
  State<FreeBooksScreen> createState() => _FreeBooksScreenState();
}

class _FreeBooksScreenState extends State<FreeBooksScreen> {
  late final CatalogueImporter _importer = CatalogueImporter(
    client: widget.client,
    bookImporter: widget.bookImporter,
  );
  late final BookOpener _opener = BookOpener(
    repository: widget.repository,
    sync: widget.sync,
  );

  final _searchController = TextEditingController();
  Timer? _debounce;

  final _entries = <CatalogueEntry>[];
  int _page = 0;
  int _loadGeneration = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  _FreeBooksProblem? _problem;

  /// Ids the reader has just imported this sitting, painted as "in your
  /// library" without waiting on a fresh [LibraryRepository.hasBook] read —
  /// the write that would answer it has barely reached the database.
  final _justImported = <String>{};

  /// One membership check per book, kept so a rebuild — every debounce tick,
  /// every scroll — does not re-query the database for a tile already
  /// answered.
  final _inLibrary = <String, Future<bool>>{};

  /// One cover fetch per book. The server proxies Gutenberg's cover bytes
  /// (ADR 0029 — never fetched directly, for CSP/COEP and Gutenberg's own
  /// missing CORS headers), and a rebuild that re-requested one per scroll
  /// frame would turn a shelf into a stream of GETs.
  final _covers = <int, Future<Uint8List?>>{};

  Future<Uint8List?> _coverOf(int gutenbergId) =>
      _covers.putIfAbsent(gutenbergId, () => _fetchCover(gutenbergId));

  // A cover that fails to load is the one partial-availability case a single
  // tile can absorb on its own: the generated face BookCoverImage already
  // falls back to is indistinguishable from "this book has no cover", which
  // is true for plenty of real Gutenberg entries too.
  Future<Uint8List?> _fetchCover(int gutenbergId) async {
    try {
      return await widget.client.cover(gutenbergId);
    } on NetworkException {
      return null;
    } on ApiException {
      return null;
    }
  }

  /// Ids currently downloading and parsing, painted with a spinner in place
  /// of the tap before the parse — which on web runs on this thread — has a
  /// chance to block a frame.
  final _importing = <String>{};

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () => _load(reset: true));
  }

  Future<bool> _checkInLibrary(String bookId) =>
      _inLibrary.putIfAbsent(bookId, () => widget.repository.hasBook(bookId));

  Future<void> _load({required bool reset}) async {
    if (reset) {
      _loadGeneration += 1;
      setState(() {
        _page = 0;
        _entries.clear();
        _hasMore = false;
        _problem = null;
        _loading = true;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    // Captured so a reset started while this request is in flight can be
    // told apart from the request it superseded: without it, a load-more or
    // an earlier search that resolves after a newer reset would append its
    // results onto the freshly-cleared list — the "list changes mid-word"
    // outcome the search field's debounce exists to prevent.
    final generation = _loadGeneration;
    final query = _searchController.text.trim();

    try {
      final result = await widget.client.search(
        q: query,
        page: _page,
        sort: query.isEmpty ? CatalogueSort.popularity : null,
      );

      if (!mounted || generation != _loadGeneration) return;

      if (!result.catalogueReady) {
        setState(() {
          _problem = _FreeBooksProblem.catalogueUnavailable;
          _loading = false;
          _loadingMore = false;
        });
        return;
      }

      setState(() {
        _entries.addAll(result.results);
        _hasMore = result.hasMore;
        _page += 1;
        _problem = _entries.isEmpty ? _FreeBooksProblem.nothingMatched : null;
        _loading = false;
        _loadingMore = false;
      });
    } on NetworkException {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _problem = _FreeBooksProblem.noConnection;
        _loading = false;
        _loadingMore = false;
      });
    } on ApiException {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _problem = _FreeBooksProblem.catalogueUnavailable;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _openOrImport(CatalogueEntry entry) async {
    if (_importing.contains(entry.bookId)) return;

    if (_justImported.contains(entry.bookId) ||
        await _checkInLibrary(entry.bookId)) {
      if (!mounted) return;
      await _opener.open(context, entry.bookId);
      return;
    }

    if (!mounted) return;

    // Painted before the download and the parse, not after: the download is
    // a real network await and yields to the event loop, but the parse
    // behind it runs inline on the UI thread on web (`BookImporter.import`),
    // and by then a spinner scheduled here has already had its frame.
    setState(() => _importing.add(entry.bookId));

    try {
      final imported = await _importer.import(entry.gutenbergId);

      await widget.repository.addBook(
        id: imported.book.id,
        title: imported.book.title,
        author: imported.book.author,
        language: imported.book.language,
        bytes: imported.bytes,
        wordCount: imported.book.text.length,
        sourceFormat: 'epub',
        coverBytes: imported.book.coverBytes,
      );

      if (!mounted) return;
      setState(() {
        _importing.remove(entry.bookId);
        _justImported.add(entry.bookId);
      });
    } on EpubException catch (e) {
      _failImport(entry, e.message);
    } on NetworkException {
      _failImport(entry, 'No internet connection. Try again.');
    } on ApiException {
      _failImport(entry, 'The catalogue is not available right now.');
    }
  }

  /// Nothing was written to the library on any of these paths — the writing
  /// `addBook` call runs after the parse succeeds — so the tile has nothing
  /// to clean up and the same tap can be retried as soon as it lands.
  void _failImport(CatalogueEntry entry, String message) {
    if (!mounted) return;
    setState(() => _importing.remove(entry.bookId));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Free books')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: TextField(
                key: freeBooksSearchFieldKey,
                controller: _searchController,
                onChanged: _onQueryChanged,
                decoration: const InputDecoration(
                  hintText: 'Search free books',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(key: freeBooksLoadingKey),
      );
    }

    if (_problem != null) {
      return _ProblemView(
        problem: _problem!,
        onRetry: () => _load(reset: true),
      );
    }

    return Column(
      children: [
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              final metrics = notification.metrics;
              if (_hasMore &&
                  !_loadingMore &&
                  metrics.pixels >=
                      metrics.maxScrollExtent - _loadMoreThreshold) {
                _load(reset: false);
              }
              return false;
            },
            child: _EntryGrid(
              entries: _entries,
              importing: _importing,
              justImported: _justImported,
              inLibraryOf: _checkInLibrary,
              coverOf: _coverOf,
              onTap: _openOrImport,
            ),
          ),
        ),
        if (_loadingMore)
          const LinearProgressIndicator(key: freeBooksLoadingMoreKey),
      ],
    );
  }
}

/// The three answers a search can come back with, none of them silence.
class _ProblemView extends StatelessWidget {
  final _FreeBooksProblem problem;
  final VoidCallback onRetry;

  const _ProblemView({required this.problem, required this.onRetry});

  String get _message => switch (problem) {
    _FreeBooksProblem.nothingMatched => 'Nothing matched your search.',
    _FreeBooksProblem.noConnection =>
      'No internet connection. Check your connection and try again.',
    _FreeBooksProblem.catalogueUnavailable =>
      'The catalogue is not available right now. Try again later.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _message,
              key: freeBooksMessageKey,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (problem != _FreeBooksProblem.nothingMatched) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                key: freeBooksRetryButtonKey,
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The results themselves, laid out the way the Library's own shelf is:
/// same tile width, same aspect ratio, cover over title over author. A
/// reader moving between "what I have" and "what I could add" meets one
/// grid shape rather than two.
class _EntryGrid extends StatelessWidget {
  final List<CatalogueEntry> entries;
  final Set<String> importing;
  final Set<String> justImported;
  final Future<bool> Function(String bookId) inLibraryOf;
  final Future<Uint8List?> Function(int gutenbergId) coverOf;
  final ValueChanged<CatalogueEntry> onTap;

  const _EntryGrid({
    required this.entries,
    required this.importing,
    required this.justImported,
    required this.inLibraryOf,
    required this.coverOf,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        var columns =
            ((constraints.maxWidth + AppSpacing.md) /
                    (AppShelf.tileWidth + AppSpacing.md))
                .floor();

        if (scaler.scale(14) > 18) columns -= 1;
        columns = columns.clamp(1, 4);

        final tileWidth =
            (constraints.maxWidth - AppSpacing.md * (columns - 1)) / columns;

        return GridView.builder(
          key: freeBooksGridKey,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.lg,
            mainAxisExtent:
                tileWidth * kCoverAspect + scaler.scale(_textBlockHeight),
          ),
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final entry = entries[i];
            return _EntryTile(
              entry: entry,
              width: tileWidth,
              importing: importing.contains(entry.bookId),
              inLibrary: justImported.contains(entry.bookId)
                  ? Future.value(true)
                  : inLibraryOf(entry.bookId),
              cover: coverOf(entry.gutenbergId),
              onTap: () => onTap(entry),
            );
          },
        );
      },
    );
  }
}

class _EntryTile extends StatelessWidget {
  final CatalogueEntry entry;
  final double width;
  final bool importing;
  final Future<bool> inLibrary;
  final Future<Uint8List?> cover;
  final VoidCallback onTap;

  const _EntryTile({
    required this.entry,
    required this.width,
    required this.importing,
    required this.inLibrary,
    required this.cover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<bool>(
      future: inLibrary,
      builder: (context, snapshot) {
        final already = snapshot.data ?? false;

        final status = importing
            ? 'Importing…'
            : already
            ? 'In your library'
            : '';

        return Semantics(
          button: true,
          label:
              '${entry.title}. ${entry.authors}. '
              '${status.isEmpty ? 'Free book' : status}',
          excludeSemantics: true,
          child: InkWell(
            key: freeBooksTileKey(entry.gutenbergId),
            onTap: importing ? null : onTap,
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    BookCoverFuture(
                      bookId: entry.bookId,
                      cover: cover,
                      width: width,
                    ),
                    if (importing)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(AppRadii.md),
                          ),
                          child: const Center(
                            child: SizedBox.square(
                              dimension: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  entry.authors,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
