import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../catalogue/catalogue_client.dart';
import '../data/library_repository.dart';
import '../sync/sync_engine.dart';
import '../theme/app_icons.dart';
import '../theme/app_tokens.dart';
import 'add_menu.dart';
import 'book_cover.dart';
import 'book_importer.dart';
import 'book_opener.dart';
import 'book_progress.dart';
import 'free_books_screen.dart';
import 'library_book.dart';
import 'note_editor_screen.dart';
import 'paste_reader_screen.dart';
import 'profile_presentation.dart';
import 'reading_display.dart';

/// Identifies the add button, for a test that would otherwise match its
/// tooltip. Same argument as `readerPlayButtonKey`: the tooltip is copy, and
/// a test asserting that a menu opens should not also assert a line of it.
const Key libraryAddButtonKey = Key('library-add-button');

/// Where the sort the reader chose is remembered. Device-local, like every
/// other `ui.` key: which order a phone shows a shelf in is not a fact about
/// the account.
const _sortKey = 'ui.library_sort';

/// Which end of that sort they are at. A second key rather than a compound
/// value under the first, since `preferences` is one row per key and a
/// compound one would need parsing on the way back out.
const _sortReversedKey = 'ui.library_sort_reversed';

/// Which formats the shelf shows. Device-local for the same reason sort is.
const _filterKey = 'ui.library_filter';

/// Which books are on screen. Filtering happens client-side, over the same
/// list [LibraryRepository.watchLibrary] already streams for sorting: a
/// second, format-scoped query would need to answer "is the *unfiltered*
/// library empty" separately from "does anything match this filter" anyway,
/// since the two states show different things, so there is nothing a SQL
/// `where` would save here.
enum _LibraryFilter {
  all('All'),
  epub('Books'),
  note('Notes');

  const _LibraryFilter(this.label);

  final String label;

  static _LibraryFilter byName(String? name) =>
      values.firstWhere((f) => f.name == name, orElse: () => all);

  bool matches(BookSummary book) =>
      matchesFormat(BookSourceFormat.fromName(book.sourceFormat));

  /// The same shelf test as [matches], answered from a source format alone.
  ///
  /// What just landed is known by format before there is a [BookSummary] to
  /// hand [matches] — an import or a saved note reports its format the
  /// moment it lands, not a full row back from the stream. Both forms are
  /// kept because a caller with a summary in hand (the shelf itself) should
  /// not have to unwrap it first.
  bool matchesFormat(BookSourceFormat format) {
    if (this == all) return true;

    final wants = this == epub ? BookSourceFormat.epub : BookSourceFormat.note;
    return format == wants;
  }
}

/// Unscaled height of everything under a cover: two lines of title, one of
/// author, the progress row, the chapter and time line, and the gaps between
/// them. Scaled with the reader's text size to give the tile its height,
/// since a fixed aspect ratio clips the moment text grows.
///
/// 96 until the place line arrived above the bar. A tile is measured rather
/// than laid out to fit, so a line added in there without a number added here
/// is a line the grid clips — the line itself and the gap that separates it
/// from the measurement under it.
const double _textBlockHeight = 118;

/// Room under the last row for the add button to float over nothing.
///
/// The button is 56 and sits 16 from the bottom edge, so a shelf ending at
/// the old 32 put the final row's menu glyph underneath it. This is the one
/// number on the screen that exists because of another widget's size.
const double _shelfBottomPadding = 88;

class LibraryScreen extends StatefulWidget {
  final LibraryRepository repository;
  final SyncEngine sync;

  /// Whether a tile's time counts down to the end of the chapter or the end
  /// of the book. Listened to for the reason Home listens: Settings is a
  /// sibling tab kept alive beside this one.
  final ReadingDisplayController display;

  /// Reaches the Catalogue for the Free books screen. Owned by [AppShell],
  /// not here — one client per app, not one per tab it happens to be opened
  /// from.
  final CatalogueClient catalogue;

  /// Carries a picked EPUB onto the shelf. Overridable so a test can stand
  /// in for the real file dialog and parse; the default builds a real
  /// [BookImporter] against [repository].
  final BookImporter? bookImporter;

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.sync,
    required this.display,
    required this.catalogue,
    this.bookImporter,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _busy = false;
  LibrarySort _sort = LibrarySort.recentlyAdded;
  bool _reversed = false;
  _LibraryFilter _filter = _LibraryFilter.all;

  /// The one path into the reader. Home's continue card takes the same
  /// object rather than its own copy of the sequence.
  late final BookOpener _opener;

  /// The same module Home and Free books carry, for the same reason.
  late final BookImporter _importer;

  /// Pacing of the profile the reader has active, for the time on each tile.
  ///
  /// The same subscription Home holds, and for the same reason: the active
  /// profile is a pointer in `preferences` naming a row in `stored_profiles`,
  /// so a figure derived from it goes stale on two separate writes and
  /// `watchActiveProfile` joins both tables to catch either.
  ///
  /// Null until the first emission. A tile shows its bar and its percentage
  /// for that frame and gains the line after, rather than showing a figure it
  /// would immediately correct.
  PacingConfig? _pacing;

  StreamSubscription<ReadingProfile>? _profile;

  LibraryRepository get _repo => widget.repository;

  @override
  void initState() {
    super.initState();
    _opener = BookOpener(repository: widget.repository, sync: widget.sync);
    _importer =
        widget.bookImporter ?? BookImporter(repository: widget.repository);
    unawaited(_restorePreferences());

    _profile = _repo.watchActiveProfile().listen((profile) {
      if (mounted) setState(() => _pacing = estimationPacing(profile));
    });

    widget.display.addListener(_onDisplayChanged);
  }

  @override
  void dispose() {
    widget.display.removeListener(_onDisplayChanged);
    _profile?.cancel();
    super.dispose();
  }

  void _onDisplayChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _restorePreferences() async {
    final sortName = await _repo.preference(_sortKey);
    final reversed = await _repo.preference(_sortReversedKey);
    final filterName = await _repo.preference(_filterKey);
    if (!mounted) return;

    setState(() {
      _sort = LibrarySort.byName(sortName);
      // Anything other than the string this writes reads as the near end,
      // which is where a reader who has never touched the control is.
      _reversed = reversed == 'true';
      _filter = _LibraryFilter.byName(filterName);
    });
  }

  Future<void> _chooseFilter(_LibraryFilter filter) async {
    if (filter == _filter) return;

    setState(() => _filter = filter);

    final hlc = await widget.sync.issueStamp();
    await _repo.setPreference(_filterKey, filter.name, hlc: hlc);
  }

  Future<void> _chooseSort(LibrarySort sort) async {
    if (sort == _sort) return;

    // The direction resets with the field. "Oldest first" and "Z to A" are
    // not the same request, and carrying a reversal across a field change
    // means the reader picks Title and gets the end they did not ask for.
    setState(() {
      _sort = sort;
      _reversed = false;
    });

    await _writeSort();
  }

  Future<void> _flipSort() async {
    setState(() => _reversed = !_reversed);
    await _writeSort();
  }

  /// Both keys, one stamp. They are one choice as far as the reader is
  /// concerned, and a crash between two writes would leave a field stored
  /// against the other field's direction.
  Future<void> _writeSort() async {
    final hlc = await widget.sync.issueStamp();

    await _repo.setPreference(_sortKey, _sort.name, hlc: hlc);
    await _repo.setPreference(_sortReversedKey, '$_reversed', hlc: hlc);
  }

  /// Asks what the reader wants to read, then does it.
  ///
  /// One entry point for both routes in. The empty state's button and the
  /// add button open this same menu rather than each wiring up its own pair
  /// of actions, which is what kept paste reachable from one screen and not
  /// the other for as long as it did.
  Future<void> _openAddMenu() async {
    final choice = await showDialog<AddChoice>(
      context: context,
      builder: (_) => const AddMenu(),
    );

    if (choice == null || !mounted) return;

    switch (choice) {
      case AddChoice.freeBooks:
        _openFreeBooks();
      case AddChoice.epub:
        await _import();
      case AddChoice.paste:
        _openPaste();
      case AddChoice.note:
        await _openNote();
    }
  }

  void _openFreeBooks() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FreeBooksScreen(
          client: widget.catalogue,
          repository: _repo,
          sync: widget.sync,
        ),
      ),
    );
  }

  /// What just landed is not on the shelf you are looking at: switch to All.
  ///
  /// One rule, asked once, rather than a branch per filter-and-format pair —
  /// an import and a saved note both land a format, and neither cares which
  /// filter it happens to displace. [_LibraryFilter.matchesFormat] is the
  /// same test the shelf itself uses to decide what's on screen.
  Future<void> _showShelfFor(BookSourceFormat format) async {
    if (!_filter.matchesFormat(format)) {
      await _chooseFilter(_LibraryFilter.all);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);

    try {
      final outcome = await _importer.importPickedFile(context);
      if (outcome != ImportOutcome.imported || !mounted) return;

      await _showShelfFor(BookSourceFormat.epub);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows the library's busy state around the shared open path.
  ///
  /// The screen keeps the flag because it decides what busy looks like here:
  /// a bar along the top while the shelf stays where it is.
  Future<void> _open(BookSummary summary) async {
    setState(() => _busy = true);

    try {
      await _opener.open(context, summary.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  Future<void> _openNote() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(repository: _repo, sync: widget.sync),
      ),
    );

    // Guarded by `saved`: backing out of the editor without writing anything
    // pops null, and resetting the filter on a cancelled add would be the
    // same wrong surprise this rule exists to remove — just triggered by
    // nothing happening rather than by something happening the reader could
    // not see.
    if (saved == true) {
      await _showShelfFor(BookSourceFormat.note);
    }
  }

  /// Opens an existing note back up for editing.
  ///
  /// Reads the stored bytes first rather than handing the editor a bookId to
  /// resolve itself: the editor's job is to compare what it started with
  /// against what it ends with, and it needs the original text in hand to do
  /// that regardless of who fetches it.
  Future<void> _editNote(BookSummary summary) async {
    final stored = await _repo.storedBookOf(summary.id);
    if (stored == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          repository: _repo,
          sync: widget.sync,
          noteId: summary.id,
          initialTitle: summary.title,
          initialBody: utf8.decode(stored.bytes, allowMalformed: true),
        ),
      ),
    );
  }

  Future<void> _addForFilter(_LibraryFilter filter) {
    return switch (filter) {
      _LibraryFilter.epub => _import(),
      _LibraryFilter.note => _openNote(),
      // Unreachable from the filtered-empty state (see _FilteredEmptyState),
      // but the general add menu is the correct fallback if it ever is.
      _LibraryFilter.all => _openAddMenu(),
    };
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
      await _repo.removeBook(summary.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wraps the whole Scaffold, not just the shelf: the FAB is a sibling of
    // the body in the widget this returns, so it needs the same snapshot the
    // body already keys its empty state off of, not a copy of its own.
    return StreamBuilder<List<BookSummary>>(
      stream: _repo.watchLibrary(sort: _sort, reversed: _reversed),
      builder: (context, snapshot) {
        final books = snapshot.data;

        return Scaffold(
          // No app bar. Its title repeated the tab label underneath it, and
          // the three actions it carried have gone: sync to settings,
          // import and paste into the add menu.
          body: SafeArea(
            // The shell owns the bottom edge, and its own Scaffold has
            // already taken the inset for the nav bar.
            bottom: false,
            child: Column(
              children: [
                // A fixed slot rather than a widget that comes and goes. The
                // bar used to live under an app bar that reserved its own
                // space; here it would push the whole shelf down four
                // pixels every time a book opened.
                SizedBox(
                  height: 4,
                  child: _busy
                      ? const LinearProgressIndicator(
                          minHeight: 4,
                          semanticsLabel: 'Working',
                        )
                      : null,
                ),
                Expanded(child: _body(books)),
              ],
            ),
          ),
          // Hidden rather than disabled while the library is empty:
          // _EmptyLibrary already carries the one button this screen needs
          // then, and a second control offering the same action reads as
          // this one being broken rather than as this one being redundant.
          // Null during the loading frame too, so the button never appears
          // for an instant only to vanish once the first snapshot lands.
          floatingActionButton: (books == null || books.isEmpty)
              ? null
              : _AddButton(onPressed: _busy ? null : _openAddMenu),
        );
      },
    );
  }

  Widget _body(List<BookSummary>? books) {
    if (books == null) {
      return const Center(child: CircularProgressIndicator());
    }
    // The whole library, not this filter's slice of it: a reader with three
    // notes and the Books filter selected has an empty shelf, not an empty
    // library, and the two want different words and a different escape
    // route. The controls row below only ever renders once there is at
    // least one book on the device to filter or sort among, so a filter
    // with nothing under it never strands the reader without a way back to
    // All.
    if (books.isEmpty) {
      return _EmptyLibrary(onAdd: _busy ? null : _openAddMenu);
    }

    final filtered = books.where(_filter.matches).toList();

    return Column(
      children: [
        _ControlsRow(
          filter: _filter,
          onFilter: _busy ? null : _chooseFilter,
          sort: _sort,
          reversed: _reversed,
          onSort: _busy ? null : _chooseSort,
          onFlip: _busy ? null : _flipSort,
        ),
        Expanded(
          child: filtered.isEmpty
              ? _FilteredEmptyState(
                  filter: _filter,
                  onAdd: _busy ? null : () => _addForFilter(_filter),
                )
              : RefreshIndicator(
                  // Pull to sync: the periodic timer is five minutes, which
                  // is a long time to wait when you have just put down
                  // another device. The status readout lives in settings
                  // now; this is the gesture, not a second copy of the
                  // state.
                  onRefresh: widget.sync.syncNow,
                  child: _BookShelf(
                    books: filtered,
                    coverOf: _repo.coverOf,
                    pacing: _pacing,
                    scope: widget.display.timeLeftScope,
                    onOpen: _busy ? null : _open,
                    onRemove: _confirmRemove,
                    onEditNote: _editNote,
                  ),
                ),
        ),
      ],
    );
  }
}

/// Screen padding: 16 below 600dp, 24 from 600dp up.
double _screenPadding(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 600 ? AppSpacing.xl : AppSpacing.lg;

/// Which books are on screen, and how they are ordered: the format filter at
/// the leading edge, the sort field and direction at the trailing one.
///
/// Was `_SortRow`, sort only. The filter joins it here rather than living in
/// a row of its own above or below: both decide what the shelf underneath
/// shows, and a reader who has just switched to Notes is a reasonable
/// candidate to reach for Sort next.
///
/// The outer `Wrap` uses `WrapAlignment.spaceBetween` rather than a `Row`,
/// for the same reason the sort controls already used a `Wrap` of their own:
/// at 360dp with doubled text the filter and the sort controls do not fit on
/// one line, and this wraps the filter onto its own line above sort rather
/// than clipping or overlapping either one.
class _ControlsRow extends StatelessWidget {
  final _LibraryFilter filter;
  final ValueChanged<_LibraryFilter>? onFilter;
  final LibrarySort sort;
  final bool reversed;
  final ValueChanged<LibrarySort>? onSort;
  final VoidCallback? onFlip;

  const _ControlsRow({
    required this.filter,
    required this.onFilter,
    required this.sort,
    required this.reversed,
    required this.onSort,
    required this.onFlip,
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
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: AppSpacing.xs,
        children: [
          PopupMenuButton<_LibraryFilter>(
            enabled: onFilter != null,
            tooltip: 'Show',
            initialValue: filter,
            onSelected: onFilter,
            itemBuilder: (context) => [
              for (final option in _LibraryFilter.values)
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
                  Text(filter.label, style: theme.textTheme.labelLarge),
                  const Icon(AppIcons.openMenu),
                ],
              ),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            children: [
              PopupMenuButton<LibrarySort>(
                enabled: onSort != null,
                tooltip: 'Sort by',
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
                      const Icon(AppIcons.openMenu),
                    ],
                  ),
                ),
              ),
              // The label says which end the list starts from rather than
              // "ascending", which means the newest books under one field
              // and the letter A under another. Pressing it reads as
              // swapping the ends, and the label changes to the end you
              // land on.
              TextButton.icon(
                onPressed: onFlip,
                icon: const Icon(AppIcons.flipSortDirection, size: 20),
                label: Text(sort.endLabel(reversed: reversed)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Opens the add menu, from anywhere on the shelf.
///
/// Takes the accent, which on this screen is the one thing that does. The
/// book tiles carry a progress fill in the same colour and that is the
/// measurement the accent is for; this is the action. Nothing else here is
/// coloured.
///
/// The shadow is [AppFloatShadow] rather than the elevation a
/// `FloatingActionButton` draws for itself, which is why every elevation on
/// it is zero. Material's own shadow is a Material 2 shape at a Material 2
/// weight, and this app decides its own shadows in one file.
class _AddButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _AddButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: dark
                  ? AppFloatShadow.ambientOpacityDark
                  : AppFloatShadow.ambientOpacityLight,
            ),
            blurRadius: AppFloatShadow.ambientBlur,
            spreadRadius: AppFloatShadow.ambientSpread,
            offset: const Offset(0, AppFloatShadow.ambientDy),
          ),
          BoxShadow(
            color: Colors.black.withValues(
              alpha: dark
                  ? AppFloatShadow.contactOpacityDark
                  : AppFloatShadow.contactOpacityLight,
            ),
            blurRadius: AppFloatShadow.contactBlur,
            spreadRadius: AppFloatShadow.contactSpread,
            offset: const Offset(0, AppFloatShadow.contactDy),
          ),
        ],
      ),
      child: FloatingActionButton(
        key: libraryAddButtonKey,
        onPressed: onPressed,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        disabledElevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        tooltip: 'Add something to read',
        child: const Icon(AppIcons.add, size: 32),
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
  final PacingConfig? pacing;
  final TimeLeftScope scope;
  final ValueChanged<BookSummary>? onOpen;
  final ValueChanged<BookSummary> onRemove;
  final ValueChanged<BookSummary> onEditNote;

  const _BookShelf({
    required this.books,
    required this.coverOf,
    required this.pacing,
    required this.scope,
    required this.onOpen,
    required this.onRemove,
    required this.onEditNote,
  });

  @override
  Widget build(BuildContext context) {
    final padding = _screenPadding(context);
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - padding * 2;
        var columns =
            ((available + AppSpacing.md) / (AppShelf.tileWidth + AppSpacing.md))
                .floor();

        // Large text needs a wider tile for the same number of words, so a
        // column comes off before anything has to ellipsize. The threshold is
        // in scaled pixels rather than in a scale factor, because that is
        // what actually decides whether a title fits.
        if (scaler.scale(14) > 18) columns -= 1;
        columns = columns.clamp(1, 4);

        if (columns == 1) {
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              padding,
              0,
              padding,
              _shelfBottomPadding,
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: books.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, i) => _BookRow(
              book: books[i],
              cover: coverOf(books[i].id),
              pacing: pacing,
              scope: scope,
              onOpen: onOpen,
              onRemove: onRemove,
              onEditNote: onEditNote,
            ),
          );
        }

        final tileWidth = (available - AppSpacing.md * (columns - 1)) / columns;

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            padding,
            0,
            padding,
            _shelfBottomPadding,
          ),
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
            pacing: pacing,
            scope: scope,
            onOpen: onOpen,
            onRemove: onRemove,
            onEditNote: onEditNote,
          ),
        );
      },
    );
  }
}

/// A book in the grid: cover, title, author (or a note's date), place.
class _BookTile extends StatelessWidget {
  final BookSummary book;
  final Future<Uint8List?> cover;
  final double width;
  final PacingConfig? pacing;
  final TimeLeftScope scope;
  final ValueChanged<BookSummary>? onOpen;
  final ValueChanged<BookSummary> onRemove;
  final ValueChanged<BookSummary> onEditNote;

  const _BookTile({
    required this.book,
    required this.cover,
    required this.width,
    required this.pacing,
    required this.scope,
    required this.onOpen,
    required this.onRemove,
    required this.onEditNote,
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
          label: semanticsForBook(book, pacing: pacing, scope: scope),
          excludeSemantics: true,
          child: InkWell(
            onTap: onOpen == null ? null : () => onOpen!(book),
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookCoverFuture(bookId: book.id, cover: cover, width: width),
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
                  )
                else if (noteDateLabel(book) case final date?)
                  Text(
                    date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                // Above the bar, not below it. The chapter belongs with the
                // author line it continues — both name what the book is —
                // while the bar and its percentage are a measurement and read
                // as the base of the tile.
                //
                // No fallback: the words that stand in for a bar when there
                // is no measurable place are already beside it, one line
                // down.
                BookPlaceLine(book: book, pacing: pacing, scope: scope),
                const SizedBox(height: AppSpacing.xs),
                BookProgressLine(book: book),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: _TileMenu(book: book, onRemove: onRemove, onEdit: onEditNote),
        ),
      ],
    );
  }
}

/// A book in the single-column layout: thumbnail beside the text.
class _BookRow extends StatelessWidget {
  final BookSummary book;
  final Future<Uint8List?> cover;
  final PacingConfig? pacing;
  final TimeLeftScope scope;
  final ValueChanged<BookSummary>? onOpen;
  final ValueChanged<BookSummary> onRemove;
  final ValueChanged<BookSummary> onEditNote;

  const _BookRow({
    required this.book,
    required this.cover,
    required this.pacing,
    required this.scope,
    required this.onOpen,
    required this.onRemove,
    required this.onEditNote,
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
            label: semanticsForBook(book, pacing: pacing, scope: scope),
            excludeSemantics: true,
            child: InkWell(
              onTap: onOpen == null ? null : () => onOpen!(book),
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BookCoverFuture(bookId: book.id, cover: cover, width: 72),
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
                          )
                        else if (noteDateLabel(book) case final date?)
                          Text(
                            date,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: AppSpacing.xs),
                        BookPlaceLine(book: book, pacing: pacing, scope: scope),
                        const SizedBox(height: AppSpacing.sm),
                        BookProgressLine(book: book),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _TileMenu(book: book, onRemove: onRemove, onEdit: onEditNote),
      ],
    );
  }
}

/// Actions that are not opening the book.
///
/// Behind a menu rather than beside the title, because one of them is
/// destructive and a mis-tap on a shelf should not start a removal.
///
/// Edit only appears for a note. An EPUB's bytes are the file the reader
/// picked; there is no text field for those to come back through, and
/// nothing to write even if there were.
class _TileMenu extends StatelessWidget {
  final BookSummary book;
  final ValueChanged<BookSummary> onRemove;
  final ValueChanged<BookSummary> onEdit;

  const _TileMenu({
    required this.book,
    required this.onRemove,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNote =
        BookSourceFormat.fromName(book.sourceFormat) == BookSourceFormat.note;

    return PopupMenuButton<String>(
      tooltip: 'More for ${book.title}',
      // A named value rather than a nullable one: PopupMenuButton reads a
      // null result as a dismissal and never calls onSelected.
      onSelected: (value) => value == 'edit' ? onEdit(book) : onRemove(book),
      itemBuilder: (context) => [
        if (isNote)
          const PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
        const PopupMenuItem<String>(value: 'remove', child: Text('Remove')),
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
          child: Icon(AppIcons.tileMenu, size: 20, color: scheme.onSurface),
        ),
      ),
    );
  }
}

/// What the shelf shows before there is a shelf.
///
/// Opens the same menu the add button does rather than importing directly.
/// The button here used to be the only way to reach paste once the library
/// had a book in it, which is how paste became unreachable at all.
class _EmptyLibrary extends StatelessWidget {
  final VoidCallback? onAdd;

  const _EmptyLibrary({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nothing here yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add an EPUB or write a note to start reading, or paste text '
              'to try it out. Books and notes stay on this device.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(minimumSize: const Size(200, 56)),
              icon: const Icon(AppIcons.add),
              label: const Text('Add something to read'),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a filtered shelf shows when nothing on it matches the filter.
///
/// Distinct from [_EmptyLibrary]: the library itself is not empty, only this
/// slice of it is, so this names the filter rather than repeating the
/// library's own empty pitch, and the [_ControlsRow] stays on screen above
/// it — switching back to All is always one tap away, never a dead end.
///
/// The button goes straight to the one action this filter can be missing:
/// file picking under Books, the note editor under Notes. It does not open
/// the general add menu, which would ask the reader to repeat a choice this
/// screen already told it.
class _FilteredEmptyState extends StatelessWidget {
  final _LibraryFilter filter;
  final VoidCallback? onAdd;

  const _FilteredEmptyState({required this.filter, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final (heading, detail, buttonLabel) = switch (filter) {
      _LibraryFilter.epub => (
        'No EPUBs yet',
        'Everything in this library so far is a note. Add a book file, '
            'or switch back to All to see the rest.',
        'Add an EPUB',
      ),
      _LibraryFilter.note => (
        'No notes yet',
        'Everything in this library so far is a book file. Write a note, '
            'or switch back to All to see the rest.',
        'Write a note',
      ),
      // build() only reaches this widget once the pre-filter list is
      // already non-empty, and the All filter matches everything in it —
      // so an empty result under All never happens.
      _LibraryFilter.all => throw StateError(
        '_FilteredEmptyState is unreachable for the all filter',
      ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(heading, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(minimumSize: const Size(200, 56)),
              icon: const Icon(AppIcons.add),
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
