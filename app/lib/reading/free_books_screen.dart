import 'dart:typed_data';

import 'package:epub_reader/epub_reader.dart';
import 'package:flutter/material.dart';

import '../catalogue/catalogue_browse.dart';
import '../catalogue/catalogue_client.dart';
import '../catalogue/language_names.dart';
import '../data/library_repository.dart';
import '../net/http_transport.dart';
import '../sync/sync_engine.dart';
import '../theme/app_icons.dart';
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

/// Identifies the message shown when a *further* page fails to load, with
/// the pages already on screen left in place.
const Key freeBooksLoadMoreErrorKey = Key('free-books-load-more-error');

/// Identifies the button that retries only the page that failed, rather
/// than the whole search.
const Key freeBooksLoadMoreRetryButtonKey = Key(
  'free-books-load-more-retry-button',
);

/// Identifies the button that reverses the current sort's direction.
const Key freeBooksReverseSortButtonKey = Key('free-books-reverse-sort-button');

/// One tile's key, so a test can find a specific book by id rather than by
/// the title it happens to carry this week.
Key freeBooksTileKey(int gutenbergId) => Key('free-books-tile-$gutenbergId');

/// How close to the bottom the grid has to scroll before the next page is
/// asked for, in logical pixels.
const double _loadMoreThreshold = 300;

/// Height of a tile's text block: two lines of title, one of author, one of
/// status. Shorter than the Library shelf's own text block, because a
/// Catalogue tile carries no place or progress line — there is nothing to
/// resume in a book not yet on this device.
const double _textBlockHeight = 96;

/// The sort control's own words, rather than [CatalogueSort]'s wire names.
extension on CatalogueSort {
  String get label => switch (this) {
    CatalogueSort.popularity => 'Most popular',
    CatalogueSort.title => 'Title',
    CatalogueSort.author => 'Author',
    CatalogueSort.issued => 'Date added',
  };
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
  final BookParser bookImporter;

  const FreeBooksScreen({
    super.key,
    required this.client,
    required this.repository,
    required this.sync,
    this.bookImporter = const BookParser(),
  });

  @override
  State<FreeBooksScreen> createState() => _FreeBooksScreenState();
}

class _FreeBooksScreenState extends State<FreeBooksScreen> {
  late final BookOpener _opener = BookOpener(
    repository: widget.repository,
    sync: widget.sync,
  );

  final _searchController = TextEditingController();

  /// The query, filters, sort, pagination position and debounce for this
  /// Browse, all of it. This screen keeps no copy of any of them: it hands
  /// the reader's actions to [_browse] and paints whatever comes back out
  /// of [CatalogueBrowse.state].
  late final CatalogueBrowse _browse = CatalogueBrowse(client: widget.client);

  /// Whether the reader has flipped the active sort off its own default
  /// direction, read back off [_browse] rather than tracked here — the
  /// reverse button is a toggle and needs to know which way it is pointing.
  bool get _reversed => _browse.reversed;

  /// The Category and Language browse lists, with their counts — fetched
  /// once and independent of [_browse]: a failure here costs the reader the
  /// counts beside "All", not the screen itself.
  List<CategoryCount> _categories = const [];
  List<LanguageCount> _languages = const [];

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
    _browse.start();
    _loadFilters();
  }

  Future<void> _loadFilters() async {
    try {
      final categories = await widget.client.categories();
      final languages = await widget.client.languages();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _languages = languages;
      });
    } on NetworkException {
      // Counts beside "All" are a convenience; browsing still works with
      // just "All" showing.
    } on ApiException {
      // Same.
    }
  }

  @override
  void dispose() {
    _browse.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String text) => _browse.queryChanged(text);

  /// The four control handlers below all wrap their call to [_browse] in
  /// `setState`. Nothing here is assigned — [_FiltersRow] paints straight off
  /// [_browse]'s own fields — but the rebuild is what puts the new choice on
  /// the chip in this frame, rather than a frame later when the [BrowseState]
  /// the call schedules reaches the [StreamBuilder] below.
  void _onCategoryChanged(String category) {
    if (category == _browse.category) return;
    setState(() => _browse.filtersChanged(category: category));
  }

  void _onLanguageChanged(String language) {
    if (language == _browse.language) return;
    setState(() => _browse.filtersChanged(language: language));
  }

  /// Picking a sort field drops any reversal with it — [CatalogueBrowse]
  /// resets direction to the new sort's own default, the same reasoning
  /// `library_screen.dart`'s `_chooseSort` gives: "Oldest first" carried
  /// over onto Title is not the request the reader made by picking Title.
  void _onSortChanged(CatalogueSort sort) {
    if (sort == _browse.sort) return;
    setState(() => _browse.filtersChanged(sort: sort));
  }

  void _onFlipDirection() => setState(_browse.toggleDirection);

  Future<bool> _checkInLibrary(String bookId) =>
      _inLibrary.putIfAbsent(bookId, () => widget.repository.hasBook(bookId));

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
    // behind it runs inline on the UI thread on web (`BookParser.import`),
    // and by then a spinner scheduled here has already had its frame.
    setState(() => _importing.add(entry.bookId));

    try {
      final bytes = await widget.client.download(entry.gutenbergId);
      final book = await widget.bookImporter.import(bytes);

      await widget.repository.addBook(book, bytes);

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
      appBar: AppBar(
        centerTitle: true,
        title: TextField(
          key: freeBooksSearchFieldKey,
          controller: _searchController,
          onChanged: _onQueryChanged,
          decoration: const InputDecoration(
            hintText: 'Search free books',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _FiltersRow(
              category: _browse.category,
              categories: _categories,
              onCategory: _onCategoryChanged,
              language: _browse.language,
              languages: _languages,
              onLanguage: _onLanguageChanged,
              sort: _browse.sort,
              onSort: _onSortChanged,
              direction: _browse.direction,
              reversed: _reversed,
              onFlip: _onFlipDirection,
            ),
            Expanded(
              // [CatalogueBrowse.state] is a broadcast stream and replays
              // nothing, so the [BrowseLoading] that `start()` emitted back in
              // `initState` — before this ever subscribed — is gone. It is the
              // initial data instead, which is the same state it stood for.
              child: StreamBuilder<BrowseState>(
                stream: _browse.state,
                initialData: const BrowseLoading(),
                builder: (context, snapshot) => _body(snapshot.data!),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One arm per [BrowseState], exhaustive — the sealed hierarchy is what
  /// stops a fourth state arriving later and landing silently in a `default`.
  Widget _body(BrowseState state) => switch (state) {
    BrowseLoading() => const Center(
      child: CircularProgressIndicator(key: freeBooksLoadingKey),
    ),
    // A first load that failed has nothing to keep, so it takes the screen.
    // Retrying it restarts the Browse from page 0.
    BrowseFailed(:final problem) => _ProblemView(
      problem: problem,
      onRetry: _browse.start,
    ),
    BrowseReady(:final entries, :final loadingMore, :final loadMoreProblem) =>
      Column(
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                final metrics = notification.metrics;
                // Unconditional past the threshold: `loadMore` already turns
                // itself away while a page is in flight, once there is no
                // further page and while a load-more problem is showing, and
                // re-deriving those guards here is how the two come apart.
                if (metrics.pixels >=
                    metrics.maxScrollExtent - _loadMoreThreshold) {
                  _browse.loadMore();
                }
                return false;
              },
              child: _EntryGrid(
                entries: entries,
                importing: _importing,
                justImported: _justImported,
                inLibraryOf: _checkInLibrary,
                coverOf: _coverOf,
                onTap: _openOrImport,
              ),
            ),
          ),
          if (loadingMore)
            const LinearProgressIndicator(key: freeBooksLoadingMoreKey),
          // Retrying here repeats only the page that failed; the pages above
          // stay exactly where the reader left them.
          if (loadMoreProblem != null)
            _LoadMoreError(
              problem: loadMoreProblem,
              onRetry: _browse.retryLoadMore,
            ),
        ],
      ),
  };
}

/// The message for each [BrowseProblem], shared by [_ProblemView] (a failed
/// first load) and [_LoadMoreError] (a failed further page) so the two never
/// drift onto different wording for the same problem.
String _problemMessage(BrowseProblem problem) => switch (problem) {
  BrowseProblem.nothingMatched => 'Nothing matched your search or filters.',
  BrowseProblem.catalogueEmpty => 'The catalogue has no books yet.',
  BrowseProblem.noConnection =>
    'No internet connection. Check your connection and try again.',
  BrowseProblem.catalogueUnavailable =>
    'The catalogue is not available right now. Try again later.',
};

/// The three answers a search can come back with, none of them silence.
class _ProblemView extends StatelessWidget {
  final BrowseProblem problem;
  final VoidCallback onRetry;

  const _ProblemView({required this.problem, required this.onRetry});

  bool get _showsRetry =>
      problem == BrowseProblem.noConnection ||
      problem == BrowseProblem.catalogueUnavailable;

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
              _problemMessage(problem),
              key: freeBooksMessageKey,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (_showsRetry) ...[
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

/// Shown under an already-loaded grid when the *next* page fails, leaving
/// the pages already on screen in place — unlike [_ProblemView], which
/// replaces the whole screen for a failed first load. [CatalogueBrowse] only
/// ever sets [BrowseReady.loadMoreProblem] to [BrowseProblem.noConnection] or
/// [BrowseProblem.catalogueUnavailable], both retryable, so the retry button
/// is unconditional here.
class _LoadMoreError extends StatelessWidget {
  final BrowseProblem problem;
  final VoidCallback onRetry;

  const _LoadMoreError({required this.problem, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _problemMessage(problem),
            key: freeBooksLoadMoreErrorKey,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            key: freeBooksLoadMoreRetryButtonKey,
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

/// Category, Language and Sort, in one `Wrap` the way Library's own
/// `_ControlsRow` wraps its filter and sort — at a wide text scale the three
/// menus do not fit one line, and this wraps the third onto its own line
/// rather than clipping or overlapping it.
///
/// Stays mounted through every [BrowseProblem]: it is a sibling of
/// `_body` in [FreeBooksScreen.build], not inside it, so a reader who
/// filtered to nothing keeps the menus that got them there rather than
/// having to back out to change them.
class _FiltersRow extends StatelessWidget {
  final String category;
  final List<CategoryCount> categories;
  final ValueChanged<String> onCategory;
  final String language;
  final List<LanguageCount> languages;
  final ValueChanged<String> onLanguage;
  final CatalogueSort sort;
  final ValueChanged<CatalogueSort> onSort;
  final CatalogueDirection direction;
  final bool reversed;
  final VoidCallback onFlip;

  const _FiltersRow({
    required this.category,
    required this.categories,
    required this.onCategory,
    required this.language,
    required this.languages,
    required this.onLanguage,
    required this.sort,
    required this.onSort,
    required this.direction,
    required this.reversed,
    required this.onFlip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          PopupMenuButton<String>(
            tooltip: 'Category',
            initialValue: category,
            onSelected: onCategory,
            itemBuilder: (context) => [
              const PopupMenuItem(value: '', child: Text('All categories')),
              for (final c in categories)
                PopupMenuItem(
                  value: c.category,
                  child: Text('${c.category} (${c.count})'),
                ),
            ],
            child: _FilterChip(
              label: category.isEmpty ? 'All categories' : category,
              theme: theme,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Language',
            initialValue: language,
            onSelected: onLanguage,
            itemBuilder: (context) => [
              const PopupMenuItem(value: '', child: Text('All languages')),
              for (final l in languages)
                PopupMenuItem(
                  value: l.language,
                  child: Text(
                    '${languageDisplayName(l.language)} (${l.count})',
                  ),
                ),
            ],
            child: _FilterChip(
              label: language.isEmpty
                  ? 'All languages'
                  : languageDisplayName(language),
              theme: theme,
            ),
          ),
          PopupMenuButton<CatalogueSort>(
            tooltip: 'Sort by',
            initialValue: sort,
            onSelected: onSort,
            itemBuilder: (context) => [
              for (final option in CatalogueSort.values)
                PopupMenuItem(value: option, child: Text(option.label)),
            ],
            child: _FilterChip(label: sort.label, theme: theme),
          ),
          // Reflects direction with `isSelected` rather than a word label:
          // unlike Library's `LibrarySort`, `CatalogueSort` names one end
          // per field, not two, so there is no "Oldest first" to swap in.
          IconButton(
            key: freeBooksReverseSortButtonKey,
            tooltip: direction == CatalogueDirection.ascending
                ? 'Ascending'
                : 'Descending',
            isSelected: reversed,
            icon: const Icon(AppIcons.flipSortDirection, size: 20),
            onPressed: onFlip,
          ),
        ],
      ),
    );
  }
}

/// One menu's closed-state label plus its opening chevron, shared by all
/// three of [_FiltersRow]'s menus so they read as one control family.
class _FilterChip extends StatelessWidget {
  final String label;
  final ThemeData theme;

  const _FilterChip({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          const Icon(AppIcons.openMenu, size: 20),
        ],
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
