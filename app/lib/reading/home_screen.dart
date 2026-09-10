import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:rsvp_engine/rsvp_engine.dart';

import '../catalogue/catalogue_client.dart';
import '../data/library_repository.dart';
import '../sync/sync_engine.dart';
import '../theme/app_icons.dart';
import '../theme/app_tokens.dart';
import '../theme/content_width.dart';
import 'add_menu_dispatcher.dart';
import 'book_cover.dart';
import 'book_opener.dart';
import 'book_progress.dart';
import 'profile_presentation.dart';
import 'reading_display.dart';
import 'section_header.dart';

/// How many books the recent row shows, beyond the one in the continue card.
const int _recentCount = 4;

/// Width the continue tile's cover is drawn at.
///
/// The same 72 the library's single-column row uses. The cover here is
/// incidental to a control, not the subject of a poster, so it takes a
/// control's size rather than a share of the tile's width (ADR 0033 §3).
const double _continueTileCoverWidth = 72;

/// Height of the progress bar along the tile's bottom edge.
const double _continueBarHeight = 4;

/// Identifies the continue tile for tests.
///
/// The tile carries one action and no button label, so a test asking which
/// book Home picked has nothing else to hold. Matching on 'Continue' was
/// doing that by accident: the label answers whether the book was started,
/// not which book is in the tile.
const Key homeContinueTileKey = Key('home-continue-tile');
const Key homeRecentlyReadHeaderKey = Key('home-recently-read-header');
const Key homeContinueOpenGlyphKey = Key('home-continue-open-glyph');

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

  /// Whether the time on the tile counts down to the end of the chapter or
  /// the end of the book. Listened to rather than read, because Settings is
  /// a sibling tab kept alive beside this one and a value read at build time
  /// would still be the old one when the reader faded back.
  final ReadingDisplayController display;

  /// Reaches the Catalogue for the Free books screen. Owned by [AppShell],
  /// not here — one client per app, not one per tab it happens to be opened
  /// from.
  final CatalogueClient catalogue;

  /// Acts on the Add menu's answer. Overridable so a test can stand in for
  /// the real file dialog and parse without a real [AddMenuDispatcher]; the
  /// default builds one against [repository], [sync] and [catalogue] —
  /// matching the Library's own [dispatcher] field.
  final AddMenuDispatcher? dispatcher;

  const HomeScreen({
    super.key,
    required this.repository,
    required this.sync,
    required this.onSeeAll,
    required this.display,
    required this.catalogue,
    this.dispatcher,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;

  /// The same sequence the library runs, not a second copy of it. ADR 0011
  /// names the shape: two paths writing one fact is how they come apart.
  late final BookOpener _opener;

  /// Acts on the Add menu's answer. The same module the Library carries —
  /// see [AddMenuDispatcher]'s own comment — built from
  /// [HomeScreen.dispatcher] when a test supplies one, so the default real
  /// importer is only ever constructed once, in [initState].
  late final AddMenuDispatcher _dispatcher;

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
    _dispatcher =
        widget.dispatcher ??
        AddMenuDispatcher(
          repository: widget.repository,
          sync: widget.sync,
          catalogue: widget.catalogue,
        );

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

  /// Opens a book, showing busy inside the continue card.
  ///
  /// Home keeps the flag rather than the opener, because Home's answer to
  /// busy is different from the library's: the card carries a spinner where
  /// its button was, and everything else on the screen stays put.
  Future<void> _open(BookSummary book) async {
    _setBusy(true);

    try {
      await _opener.open(context, book.id);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _openAddMenu() =>
      _dispatcher.showAndAct(context, onBusy: _setBusy);

  /// Shows busy as a spinner in place of the continue card's glyph, and
  /// nowhere else on the screen.
  ///
  /// Raised from [AddMenuDispatcher.act]'s `onBusy`, which only fires once an
  /// EPUB pick has bytes — see [BookImporter.importPickedFile]'s `onPicked`
  /// — so cancelling the file chooser never toggles `_busy` at all (#269),
  /// and neither does the wait for the reader's tap on the menu itself,
  /// since nothing is raised until an answer exists. The other three choices
  /// never raise it: none is slow enough for a reader to notice. A failed
  /// import is reported once, by [AddMenuDispatcher]'s own [BookImporter];
  /// this only covers how long the spinner shows.
  void _setBusy(bool busy) {
    if (mounted) setState(() => _busy = busy);
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
                        child: ContentWidth(
                          child: _NothingOpenYet(
                            onAdd: _busy ? null : _openAddMenu,
                          ),
                        ),
                      ),
                    );
                  }

                  return Center(
                    child: ContentWidth(
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
                            cover: _repo.coverOf(recent.first.id),
                            pacing: _pacing,
                            scope: widget.display.timeLeftScope,
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
                                  child: SectionHeader(
                                    'Recently read',
                                    key: homeRecentlyReadHeaderKey,
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                                // Appears only when there is a book the row
                                // cannot show. An arrow that is always
                                // there promises more than four whether or
                                // not there are more.
                                if (recent.length > _recentCount + 1)
                                  IconButton(
                                    onPressed: widget.onSeeAll,
                                    icon: const Icon(AppIcons.seeAll),
                                    tooltip: 'All books',
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _RecentRow(
                              books: recent.skip(1).take(_recentCount).toList(),
                              coverOf: _repo.coverOf,
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
  sorted.sort((a, b) {
    final byActivity = _activityOf(b).compareTo(_activityOf(a));
    if (byActivity != 0) return byActivity;

    // Drift stores DateTime columns at whole-second precision, so a book
    // read right after being imported can tie its own import on the
    // timestamp that survives the round trip through the database. A tie
    // still has a right answer: a book that has actually been opened
    // outranks one that has only ever been added.
    final aRead = _hasBeenRead(a);
    final bRead = _hasBeenRead(b);
    if (aRead == bRead) return 0;
    return aRead ? -1 : 1;
  });

  return sorted;
}

DateTime _activityOf(BookSummary book) => book.lastReadAt ?? book.importedAt;

bool _hasBeenRead(BookSummary book) => book.lastReadAt != null;

/// The tile that gets a reader back into the book they're in.
///
/// No heading over it. The tile shows a cover, a title, an author, where
/// the reader is and how much is left, which is the section's subject
/// stated five times already.
class _ContinueSection extends StatelessWidget {
  final BookSummary book;
  final Future<Uint8List?> cover;
  final PacingConfig? pacing;
  final TimeLeftScope scope;
  final bool busy;
  final ValueChanged<BookSummary>? onOpen;

  const _ContinueSection({
    required this.book,
    required this.cover,
    required this.pacing,
    required this.scope,
    required this.busy,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) => _ContinueTile(
    book: book,
    cover: cover,
    pacing: pacing,
    scope: scope,
    busy: busy,
    onOpen: onOpen,
  );
}

/// The book the reader is in, with the way back into it.
///
/// One tile, and the tap is the tile. A small cover sits on the left, the
/// same 72 the library's single-column row uses, with the title and author
/// beside it and the way in opposite them on the right. Under the author is
/// one dim line saying how much of the book is left, which is the question
/// a reader picking a book up again actually has. The cover is incidental
/// to a control, not the subject of a poster (ADR 0033 §3), so it no longer
/// reserves a large placeholder height for books without stored art.
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
  final TimeLeftScope scope;
  final bool busy;
  final ValueChanged<BookSummary>? onOpen;

  const _ContinueTile({
    required this.book,
    required this.cover,
    required this.pacing,
    required this.scope,
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

    return Semantics(
      button: true,
      label: semanticsForBook(book, pacing: pacing, scope: scope),
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
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BookCoverFuture(
                        bookId: book.id,
                        cover: cover,
                        width: _continueTileCoverWidth,
                      ),
                      const SizedBox(width: AppSpacing.md),
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
                            // The chapter and the estimate, and the words
                            // that stand in for a bar where there is
                            // neither. All of them answer "how far in am I";
                            // none is worth a line of its own.
                            BookPlaceLine(
                              book: book,
                              pacing: pacing,
                              scope: scope,
                              fallback: progress.label,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      SizedBox(
                        height: _continueTileCoverWidth * kCoverAspect,
                        child: Center(
                          child: _OpenGlyph(
                            key: homeContinueOpenGlyphKey,
                            busy: busy,
                            enabled: onOpen != null,
                          ),
                        ),
                      ),
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

  const _OpenGlyph({super.key, required this.busy, required this.enabled});

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
            : Icon(AppIcons.resume, size: 32, color: colour),
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
/// One button opening the Add menu, matching the library's own empty state,
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
            style: FilledButton.styleFrom(
              minimumSize: AppButton.contentMinSize,
            ),
            icon: const Icon(AppIcons.add),
            label: const Text('Add something to read'),
          ),
        ),
      ],
    );
  }
}
