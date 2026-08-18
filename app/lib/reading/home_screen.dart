import 'dart:async';
import 'dart:typed_data';

import 'package:epub_reader/epub_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import '../sync/sync_engine.dart';
import '../theme/app_tokens.dart';
import 'add_menu.dart';
import 'book_cover.dart';
import 'book_opener.dart';
import 'book_progress.dart';
import 'library_book.dart';
import 'note_editor_screen.dart';
import 'paste_reader_screen.dart';

/// How many books the recent row shows, beyond the one in the continue card.
const int _recentCount = 4;

/// Widest the column of content gets. Past this the screen stops growing
/// and centres, because a 1600px-wide continue tile is a banner.
const double _maxContentWidth = 720;

/// Width of the continue tile.
///
/// Fixed rather than a share of the screen. The cover runs the tile's full
/// width and is half again as tall, so every pixel of width costs one and a
/// half of height, and a tile that tracked a desktop window would be a
/// hero image.
const double _continueTileMaxWidth = 252;

/// Height of the progress bar along the tile's bottom edge.
const double _continueBarHeight = 4;

/// Identifies the continue tile for tests.
///
/// The tile carries one action and no button label, so a test asking which
/// book Home picked has nothing else to hold. Matching on 'Continue' was
/// doing that by accident: the label answers whether the book was started,
/// not which book is in the tile.
const Key homeContinueTileKey = Key('home-continue-tile');

/// The first screen, and the one that answers "where was I".
///
/// Ordered by when a book was last read rather than when it arrived. Those
/// are different questions and the library already answers the other one:
/// a book imported this morning and never opened does not belong above the
/// one the reader was in last night.
class HomeScreen extends StatefulWidget {
  final LibraryRepository repository;
  final SyncEngine sync;

  /// Switches to the Library tab. Home shows four recent books and no
  /// scroll, so the fifth has to go somewhere, and the screen that lists
  /// every book already exists.
  final VoidCallback onSeeAll;

  /// Stamps anything the paste screen writes. Taken as a function rather
  /// than reached through [sync], so a widget test can supply one without
  /// standing up a clock, an auth store and a device id it has no use for.
  final Future<String> Function() issueStamp;

  const HomeScreen({
    super.key,
    required this.repository,
    required this.sync,
    required this.onSeeAll,
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

  /// Pacing of the profile the reader has active, for the time estimate.
  ///
  /// Watched rather than read once. The profile is changed in two places
  /// this screen never hears from otherwise: the sheet on the reading
  /// screen, and Settings, which is a sibling tab kept alive beside this
  /// one. A figure in minutes drawn from a profile the reader has just
  /// replaced is wrong in the one way an estimate must not be, which is
  /// quietly.
  ///
  /// Null until the first emission, and the tile falls back to the words
  /// `progressOf` supplies for that frame rather than showing a figure it
  /// would immediately correct.
  PacingConfig? _pacing;

  StreamSubscription<ReadingProfile>? _profile;

  @override
  void initState() {
    super.initState();
    _opener = BookOpener(repository: widget.repository, sync: widget.sync);

    _profile = _repo.watchActiveProfile().listen((profile) {
      if (mounted) setState(() => _pacing = profile.pacing);
    });
  }

  @override
  void dispose() {
    _profile?.cancel();
    super.dispose();
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

  /// Asks what the reader wants to read, then does it.
  ///
  /// The same menu the library's add button opens, not a shorter version of
  /// its own — see [AddMenu]'s own comment for why Home used to carry a
  /// second, incomplete copy of this choice.
  Future<void> _openAddMenu() async {
    final choice = await showDialog<AddChoice>(
      context: context,
      builder: (_) => const AddMenu(),
    );

    if (choice == null || !mounted) return;

    switch (choice) {
      case AddChoice.epub:
        await _import();
      case AddChoice.paste:
        _openPaste();
      case AddChoice.note:
        _openNote();
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
        sourceFormat: 'epub',
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
        builder: (_) =>
            PasteReaderScreen(repository: _repo, issueStamp: widget.issueStamp),
      ),
    );
  }

  void _openNote() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(repository: _repo, sync: widget.sync),
      ),
    );
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
      // No app bar and no controls in the corners. The navigation names
      // this tab, and the two icons that were up here were a sync readout
      // nobody opens Home to check and a paste entry the shared add menu
      // (see add_menu.dart) now carries instead.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<BookSummary>>(
                stream: _repo.watchLibrary(),
                builder: (context, snapshot) {
                  final books = snapshot.data;
                  if (books == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final recent = byLastRead(books);

                  if (recent.isEmpty) {
                    // Centred rather than laid out from the top. There is
                    // one thing on this screen and no reason for it to sit
                    // under an edge with the rest of the window empty.
                    // Still scrollable: nothing clamps the reader's text
                    // size, so two buttons and a sentence can outgrow a
                    // short window.
                    return Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(_screenPadding(context)),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _maxContentWidth,
                          ),
                          child: _NothingOpenYet(
                            onAdd: _busy ? null : _openAddMenu,
                          ),
                        ),
                      ),
                    );
                  }

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _maxContentWidth,
                      ),
                      child: ListView(
                        // Well off the top. The tile is the only thing up
                        // there and it reads as pinned to the status bar
                        // without this.
                        padding: EdgeInsets.fromLTRB(
                          _screenPadding(context),
                          AppSpacing.xxxl,
                          _screenPadding(context),
                          AppSpacing.md,
                        ),
                        children: [
                          _ContinueSection(
                            book: recent.first,
                            cover: _coverOf(recent.first.id),
                            pacing: _pacing,
                            busy: _busy,
                            onOpen: _busy ? null : _open,
                          ),
                          // Between here and Recent sits the stats strip
                          // section 7.1 reserves. Nothing renders there
                          // until there are stats worth reading; a box
                          // explaining what will eventually arrive is the
                          // placeholder that section rules out.
                          if (recent.length > 1) ...[
                            const SizedBox(height: AppSpacing.xxl),
                            Row(
                              children: [
                                const Expanded(
                                  child: _SectionLabel('Recently read'),
                                ),
                                // Appears only when there is a book the row
                                // cannot show. An arrow that is always
                                // there promises more than four whether or
                                // not there are more.
                                if (recent.length > _recentCount + 1)
                                  IconButton(
                                    onPressed: widget.onSeeAll,
                                    icon: const Icon(Icons.arrow_forward),
                                    tooltip: 'All books',
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _RecentRow(
                              books: recent.skip(1).take(_recentCount).toList(),
                              coverOf: _coverOf,
                              onOpen: _busy ? null : _open,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xxl),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
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

/// The tile, held to one width.
///
/// No heading over it. The tile shows a cover, a title, an author, where
/// the reader is and how much is left, which is the section's subject
/// stated five times already.
class _ContinueSection extends StatelessWidget {
  final BookSummary book;
  final Future<Uint8List?> cover;
  final PacingConfig? pacing;
  final bool busy;
  final ValueChanged<BookSummary>? onOpen;

  const _ContinueSection({
    required this.book,
    required this.cover,
    required this.pacing,
    required this.busy,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _continueTileMaxWidth),
      child: _ContinueTile(
        book: book,
        cover: cover,
        pacing: pacing,
        busy: busy,
        onOpen: onOpen,
      ),
    ),
  );
}

/// The book the reader is in, with the way back into it.
///
/// One tile, and the tap is the tile. The cover runs the tile's full width
/// and reaches its top edge, the title and author sit under it on the left,
/// and the way in sits opposite them on the right. Under the author is one
/// dim line saying how much of the book is left, which is the question a
/// reader picking a book up again actually has.
///
/// The glyph is not a button. A tile that opens the book, carrying a
/// control that opens the book, gives one action two targets, and the outer
/// one swallows the reader's aim for the inner. Drawing the glyph and
/// taking the tap on the tile keeps the target the size of the tile.
///
/// Accent appears once, on the filled part of the bar. The glyph stays
/// neutral: two accented marks inside one container and neither of them
/// reads as the important one.
class _ContinueTile extends StatelessWidget {
  final BookSummary book;
  final Future<Uint8List?> cover;
  final PacingConfig? pacing;
  final bool busy;
  final ValueChanged<BookSummary>? onOpen;

  const _ContinueTile({
    required this.book,
    required this.cover,
    required this.pacing,
    required this.busy,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hairline = theme.dividerTheme.thickness ?? AppHairline.width;
    final dark = theme.brightness == Brightness.dark;
    final progress = progressOf(book);

    // The estimate where there is one, and the words that stand in for a
    // bar where there is not. Both answer "how far in am I"; neither is
    // worth its own line, and a book whose word count predates the column
    // falls back rather than showing nothing.
    final config = pacing;
    final remaining = config == null ? null : remainingLabel(book, config);

    return Semantics(
      button: true,
      label: semanticsForBook(book),
      excludeSemantics: true,
      child: Container(
        key: homeContinueTileKey,
        // Clipped by the container that draws the border, rather than by a
        // ClipRRect inside it. The bar runs to both bottom corners and has
        // to take their curve; the border draws over the clip, so it stays
        // an unbroken hairline around the whole shape.
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          // Opaque, and the same colour as the screen behind it. The fill
          // is not there to be seen: a BoxShadow paints a blurred copy of
          // the shape underneath the box, so a transparent tile shows its
          // own shadow through its middle.
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: scheme.outlineVariant, width: hairline),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(
                alpha: dark
                    ? AppShadow.ambientOpacityDark
                    : AppShadow.ambientOpacityLight,
              ),
              blurRadius: AppShadow.ambientBlur,
              spreadRadius: AppShadow.ambientSpread,
              offset: const Offset(0, AppShadow.ambientDy),
            ),
            BoxShadow(
              color: scheme.shadow.withValues(
                alpha: dark
                    ? AppShadow.contactOpacityDark
                    : AppShadow.contactOpacityLight,
              ),
              blurRadius: AppShadow.contactBlur,
              spreadRadius: AppShadow.contactSpread,
              offset: const Offset(0, AppShadow.contactDy),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onOpen == null ? null : () => onOpen!(book),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;

                    // The cover runs edge to edge and flush to the top, so
                    // the tile's own clip gives it the top corners. Its
                    // bottom corners are cropped off: BookCoverFuture
                    // rounds all four, and a curve there would leave the
                    // tile's surface showing in two notches against sides
                    // that are otherwise straight.
                    final height = width * kCoverAspect;

                    return ClipRect(
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: (height - AppRadii.md) / height,
                        child: BookCoverFuture(
                          bookId: book.id,
                          cover: cover,
                          width: width,
                        ),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              book.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                            if (book.author != null)
                              Text(
                                book.author!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              remaining ?? progress.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      _OpenGlyph(busy: busy, enabled: onOpen != null),
                    ],
                  ),
                ),
                _ProgressEdge(value: progress.value),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The mark opposite the title, and where the spinner goes while a book
/// opens.
///
/// Sized to a button without being one, so the tile's own tap target keeps
/// its full area and the glyph still reads as somewhere to press.
class _OpenGlyph extends StatelessWidget {
  final bool busy;
  final bool enabled;

  const _OpenGlyph({required this.busy, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colour = enabled ? scheme.onSurface : scheme.onSurfaceVariant;

    return SizedBox.square(
      dimension: 40,
      child: Center(
        child: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.play_circle_outline, size: 32, color: colour),
      ),
    );
  }
}

/// The tile's bottom edge, drawn as how far through the book the reader is.
///
/// Built from two boxes rather than a `LinearProgressIndicator`. Material 3
/// draws a stop indicator and a gap before the head of the bar, which reads
/// as damage once the bar is an edge of something rather than a control
/// inside it.
class _ProgressEdge extends StatelessWidget {
  /// Fraction read, or null when the book has no measurable place.
  final double? value;

  const _ProgressEdge({required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = value;

    return SizedBox(
      height: _continueBarHeight,
      child: Stack(
        children: [
          // The track runs the full width whether or not there is a
          // fraction to draw on it, so the edge of the tile does not appear
          // and disappear with the reader's progress.
          Positioned.fill(
            child: ColoredBox(color: scheme.surfaceContainerHighest),
          ),
          if (fraction != null)
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction.clamp(0.0, 1.0),
                child: ColoredBox(color: scheme.primary),
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
    // Four columns, always, whether or not there are four books. A row that
    // sized itself to what it had would draw one enormous cover for a
    // library of two and shrink as the reader imported more.
    return Row(
      spacing: AppSpacing.md,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _recentCount; i++)
          Expanded(
            child: i < books.length
                ? _RecentTile(
                    book: books[i],
                    cover: coverOf(books[i].id),
                    onOpen: onOpen,
                  )
                : const SizedBox.shrink(),
          ),
      ],
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
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              BookCoverFuture(
                bookId: book.id,
                cover: cover,
                width: constraints.maxWidth,
              ),
              const SizedBox(height: AppSpacing.xs),
              // One line, not two. Four columns on a phone truncate most
              // titles either way, and the cover is what the reader
              // recognises a book they have read by.
              Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What Home shows before there is anything to continue.
///
/// One button opening [AddMenu], matching the library's own empty state,
/// rather than two buttons of its own. It used to be two — EPUB and paste,
/// with no way to reach the note editor at all — which was never a decision
/// to leave notes out of this screen specifically; it was this widget having
/// its own copy of a choice the library already owned, and the two drifting
/// out of sync the moment a third option was added to one of them.
class _NothingOpenYet extends StatelessWidget {
  final VoidCallback? onAdd;

  const _NothingOpenYet({required this.onAdd});

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
          'Add an EPUB or write a note to begin, or paste text to try it '
          'out. Books and notes stay on this device.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xl),
        Center(
          child: FilledButton.icon(
            onPressed: onAdd,
            style: FilledButton.styleFrom(minimumSize: const Size(200, 56)),
            icon: const Icon(Icons.add),
            label: const Text('Add something to read'),
          ),
        ),
      ],
    );
  }
}
