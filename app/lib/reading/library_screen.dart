import 'dart:async';
import 'dart:typed_data';

import 'package:epub_reader/epub_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../sync/sync_engine.dart';
import '../theme/app_tokens.dart';
import 'book_cover.dart';
import 'book_opener.dart';
import 'book_progress.dart';
import 'library_book.dart';
import 'paste_reader_screen.dart';

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

/// Width a tile aims for before the column count is worked out.
const double _targetTileWidth = 172;

/// Unscaled height of everything under a cover: two lines of title, one of
/// author, the progress row, and the gaps between them. Scaled with the
/// reader's text size to give the tile its height, since a fixed aspect ratio
/// clips the moment text grows.
const double _textBlockHeight = 96;

/// Room under the last row for the add button to float over nothing.
///
/// The button is 56 and sits 16 from the bottom edge, so a shelf ending at
/// the old 32 put the final row's menu glyph underneath it. This is the one
/// number on the screen that exists because of another widget's size.
const double _shelfBottomPadding = 88;

/// What the add menu came back with.
enum _AddChoice { epub, paste }

class LibraryScreen extends StatefulWidget {
  final LibraryRepository repository;
  final SyncEngine sync;

  /// Stamps the sort preference. Taken as a function rather than reached
  /// through [sync], so a widget test can supply one without standing up a
  /// clock, an auth store and a device id it has no use for.
  final Future<String> Function() issueStamp;

  const LibraryScreen({
    super.key,
    required this.repository,
    required this.sync,
    required this.issueStamp,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _busy = false;
  LibrarySort _sort = LibrarySort.recentlyAdded;
  bool _reversed = false;

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
    final reversed = await _repo.preference(_sortReversedKey);
    if (!mounted) return;

    setState(() {
      _sort = LibrarySort.byName(stored);
      // Anything other than the string this writes reads as the near end,
      // which is where a reader who has never touched the control is.
      _reversed = reversed == 'true';
    });
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
    final hlc = await widget.issueStamp();

    await _repo.setPreference(_sortKey, _sort.name, hlc: hlc);
    await _repo.setPreference(_sortReversedKey, '$_reversed', hlc: hlc);
  }

  Future<Uint8List?> _coverOf(String bookId) =>
      _covers.putIfAbsent(bookId, () => _repo.coverOf(bookId));

  /// Asks what the reader wants to read, then does it.
  ///
  /// One entry point for both routes in. The empty state's button and the
  /// add button open this same menu rather than each wiring up its own pair
  /// of actions, which is what kept paste reachable from one screen and not
  /// the other for as long as it did.
  Future<void> _openAddMenu() async {
    final choice = await showDialog<_AddChoice>(
      context: context,
      builder: (_) => const _AddMenu(),
    );

    if (choice == null || !mounted) return;

    switch (choice) {
      case _AddChoice.epub:
        await _import();
      case _AddChoice.paste:
        _openPaste();
    }
  }

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
      // No app bar. Its title repeated the tab label underneath it, and the
      // three actions it carried have gone: sync to settings, import and
      // paste into the add menu.
      body: SafeArea(
        // The shell owns the bottom edge, and its own Scaffold has already
        // taken the inset for the nav bar.
        bottom: false,
        child: Column(
          children: [
            // A fixed slot rather than a widget that comes and goes. The bar
            // used to live under an app bar that reserved its own space;
            // here it would push the whole shelf down four pixels every time
            // a book opened.
            SizedBox(
              height: 4,
              child: _busy
                  ? const LinearProgressIndicator(
                      minHeight: 4,
                      semanticsLabel: 'Working',
                    )
                  : null,
            ),
            Expanded(
              child: StreamBuilder<List<BookSummary>>(
                stream: _repo.watchLibrary(sort: _sort, reversed: _reversed),
                builder: (context, snapshot) {
                  final books = snapshot.data;
                  if (books == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (books.isEmpty) {
                    return _EmptyLibrary(onAdd: _busy ? null : _openAddMenu);
                  }

                  return Column(
                    children: [
                      _SortRow(
                        sort: _sort,
                        reversed: _reversed,
                        onSort: _busy ? null : _chooseSort,
                        onFlip: _busy ? null : _flipSort,
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          // Pull to sync: the periodic timer is five minutes,
                          // which is a long time to wait when you have just
                          // put down another device. The status readout lives
                          // in settings now; this is the gesture, not a
                          // second copy of the state.
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
            ),
          ],
        ),
      ),
      floatingActionButton: _AddButton(
        onPressed: _busy ? null : _openAddMenu,
      ),
    );
  }
}

/// Screen padding: 16 below 600dp, 24 from 600dp up.
double _screenPadding(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 600 ? AppSpacing.xl : AppSpacing.lg;

/// The field to sort on, and which end of it to start from.
///
/// Two controls rather than one list of every combination. Six entries in a
/// menu is a list the reader reads to find the one they want; a field and an
/// end is two decisions they already have in mind. It also stops the menu
/// growing by two every time a sort is added.
///
/// A `Wrap` rather than a `Row`. At 360dp with doubled text the two labels do
/// not fit on one line, and a low-vision app clipping the word that says
/// which order the shelf is in has failed at the one thing this row does.
class _SortRow extends StatelessWidget {
  final LibrarySort sort;
  final bool reversed;
  final ValueChanged<LibrarySort>? onSort;
  final VoidCallback? onFlip;

  const _SortRow({
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
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          // The label says which end the list starts from rather than
          // "ascending", which means the newest books under one field and
          // the letter A under another. Pressing it reads as swapping the
          // ends, and the label changes to the end you land on.
          TextButton.icon(
            onPressed: onFlip,
            icon: const Icon(Icons.swap_vert, size: 20),
            label: Text(sort.endLabel(reversed: reversed)),
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
        child: const Icon(Icons.add, size: 32),
      ),
    );
  }
}

/// Two ways to start reading, one above the other.
///
/// Halves rather than a list of rows. There are two of these and there is no
/// third coming that is not a file or a paste, so each one takes half the
/// panel and the whole half is the tap target. A reader who cannot reliably
/// hit a small target gets a box the size of a hand instead of a 48dp row.
///
/// Each half says what it does and what happens to it afterwards. The
/// difference between the two is not the source of the text, it is whether
/// the thing survives closing the app, and a reader finding that out later
/// is a reader who lost something.
class _AddMenu extends StatelessWidget {
  const _AddMenu();

  /// Wide enough to hold two lines of explanation on a phone, capped before
  /// it becomes a dialog the width of a monitor holding two words.
  static const double _maxWidth = 480;

  /// Tall enough that each half is a target rather than a row. Grows with
  /// the reader's text size; the whole panel scrolls once it has to.
  static const double _minHalfHeight = 148;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Add something to read',
      child: Dialog(
        // Clipped so an ink ripple in either half stops at the rounded
        // corner rather than painting over it.
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: theme.dividerTheme.thickness ?? AppHairline.width,
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _maxWidth,
            maxHeight: size.height * 0.8,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AddMenuHalf(
                  choice: _AddChoice.epub,
                  icon: Icons.upload_file,
                  title: 'Add an EPUB',
                  detail: 'A book file from this device. It stays in your '
                      'library and remembers your place.',
                  minHeight: _minHalfHeight,
                ),
                // Takes its colour and weight from the app's one divider
                // theme, so it thickens with the rest of them under high
                // contrast.
                const Divider(),
                _AddMenuHalf(
                  choice: _AddChoice.paste,
                  icon: Icons.content_paste,
                  title: 'Paste text',
                  detail: 'Read anything you have copied. Nothing is saved, '
                      'and it is gone when you close it.',
                  minHeight: _minHalfHeight,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddMenuHalf extends StatelessWidget {
  final _AddChoice choice;
  final IconData icon;
  final String title;
  final String detail;
  final double minHeight;

  const _AddMenuHalf({
    required this.choice,
    required this.icon,
    required this.title,
    required this.detail,
    required this.minHeight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      label: '$title. $detail',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(choice),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: scheme.onSurface),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
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
              onOpen: onOpen,
              onRemove: onRemove,
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
            onOpen: onOpen,
            onRemove: onRemove,
          ),
        );
      },
    );
  }
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
          label: semanticsForBook(book),
          excludeSemantics: true,
          child: InkWell(
            onTap: onOpen == null ? null : () => onOpen!(book),
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookCoverFuture(
                  bookId: book.id,
                  title: book.title,
                  cover: cover,
                  width: width,
                ),
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
                BookProgressLine(book: book),
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
            label: semanticsForBook(book),
            excludeSemantics: true,
            child: InkWell(
              onTap: onOpen == null ? null : () => onOpen!(book),
              borderRadius: BorderRadius.circular(AppRadii.md),
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
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
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
        _TileMenu(book: book, onRemove: onRemove),
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
              'No books yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add an EPUB to start reading, or paste text to try it out. '
              'Books stay on this device.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(minimumSize: const Size(200, 56)),
              icon: const Icon(Icons.add),
              label: const Text('Add something to read'),
            ),
          ],
        ),
      ),
    );
  }
}
