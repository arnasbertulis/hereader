import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'library_book.dart';
import 'profile_presentation.dart';
import 'rsvp_view.dart';

/// Identifies the play and pause button on the reading surface.
///
/// The button carried a text label until ADR 0015, and five tests across
/// `reader_progress_test.dart` and `reader_semantics_test.dart` reached it
/// with `find.text('Read')`. Each of those was asserting two things: that
/// playback starts, and that the control says a particular word. A key
/// asserts the first alone, as `homeContinueTileKey` and `appNavBarKey`
/// already do for Home and the shell.
const Key readerPlayButtonKey = Key('reader-play-button');

/// Where the reader stopped.
///
/// The token index travels alongside the locator because the service has no
/// copy of the book and cannot work out how far apart two positions are
/// without it. The locator remains the authoritative position; this is only
/// a hint for judging divergence.
class ReadingResult {
  final Locator locator;
  final int tokenIndex;

  const ReadingResult({required this.locator, required this.tokenIndex});
}

/// Full-screen reading surface for a book.
///
/// Decides when a position is worth writing and hands it to [onSave]. How it
/// is written — one transaction covering the position row and the outbox — is
/// the repository's business and not this screen's. The route used to pop
/// with a [ReadingResult] instead; two paths writing one fact is how they
/// come apart, and only one of them could ever fire.
class ReaderScreen extends StatefulWidget {
  final LibraryBook book;
  final LibraryRepository repository;

  /// Supplies a clock stamp. Pass `syncEngine.issueStamp`.
  final Future<String> Function() issueStamp;

  /// Called whenever the reader's place is worth recording: on every
  /// deliberate stop, every fifteen seconds of movement between them, when
  /// the app is hidden, and when the book closes. See ADR 0011.
  ///
  /// Pasted text passes one that does nothing. It has no book row, so a
  /// position against it would fail the foreign key.
  final Future<void> Function(ReadingResult) onSave;

  const ReaderScreen({
    super.key,
    required this.book,
    required this.repository,
    required this.issueStamp,
    required this.onSave,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final PlaybackSession _session;
  StreamSubscription<PlaybackUpdate>? _sub;

  /// The frame the reading surface is drawing.
  ///
  /// A notifier rather than a field behind `setState`, because a word
  /// replacing another is the only thing that changes between two frames of
  /// ordinary playback. Rebuilding this State rebuilt the Scaffold, the
  /// chapter panel, the controls and everything between them four to nine
  /// times a second in order to move one word.
  final _current = ValueNotifier<PlaybackUpdate?>(null);

  /// Fires while the reader is moving. Sixty words at 250 wpm, so a crash
  /// costs a sentence or two.
  static const _saveInterval = Duration(seconds: 15);

  Timer? _saveTimer;
  AppLifecycleListener? _lifecycle;

  /// Watched for transitions into a stopped state, which is what makes a
  /// pause, a chapter jump and a profile switch all save without each one
  /// having to remember to.
  late PlaybackState _lastState;

  /// The index already on disk. A tick that finds it unchanged returns
  /// without a transaction, so a paused reader writes nothing at all — a
  /// finished one still does, forced, since reaching the end of a one-token
  /// text finds it unchanged too. See [_save]'s `force` parameter.
  late int _lastSavedIndex;

  /// Whether to tell the reader this book opened past a guess.
  ///
  /// Front matter detection returns an index and a reason. A marker the book
  /// supplied needs no comment; a pattern match is capped at fifteen percent
  /// of the file and can still take a dedication that reads like a rights
  /// line, and a guess the reader was never shown is one they cannot correct.
  bool _offerFrontMatter = false;

  /// Held so the chapter button can open the drawer and the back gesture can
  /// ask whether it is open. The button sits inside the Scaffold's body, so
  /// `Scaffold.of` would work for it alone, but the pop handler is built
  /// above the Scaffold and cannot reach it that way.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Standard until the stored choice loads. The session is built
  /// synchronously in [initState] and reading can begin before a database
  /// read returns, so the profile is swapped in rather than waited for.
  ReadingProfile _profile = Presets.standard;

  @override
  void initState() {
    super.initState();
    _session = PlaybackSession(
      tokens: widget.book.text.tokens,
      profile: _profile,
      startIndex: widget.book.resumeIndex,
    );

    // Seeded rather than waited for. The stream carries changes, and a
    // session nobody has touched has not changed, so a book opened at a
    // stored position drew an empty surface until the reader pressed
    // something. Caught by the front matter test, which asked what was on
    // screen at open — nothing else ever had.
    _current.value = _session.current;

    _lastState = _session.state;

    // Seeded from where the book opened, so glancing at a book and closing it
    // writes nothing and issues no stamp. The exception is a position that
    // did not resolve against this copy: the reader's place here is then
    // genuinely new information rather than a repeat of what is stored.
    _lastSavedIndex = widget.book.positionUnresolvable ? -1 : _session.index;

    // Only on a first open. A reader resuming made this decision, or lived
    // with it, sittings ago.
    _offerFrontMatter =
        widget.book.position == null && widget.book.skippedFrontMatterOnAGuess;

    _sub = _session.updates.listen((u) {
      if (!mounted) return;

      // Unconditional. This is what the reading surface draws from, and it
      // is the only thing that changes while a stream of words is playing.
      _current.value = u;

      final stopped =
          u.state == PlaybackState.paused || u.state == PlaybackState.finished;

      // On the transition rather than on every update, so the second emit
      // seekToIndex produces does not queue a second write.
      //
      // Forced on finished regardless of whether the index moved. A text of
      // one token starts and finishes at the same index, so the ordinary
      // "unchanged, nothing to save" guard in _save would otherwise treat
      // finishing it exactly like the glance-and-close it is built to
      // ignore, and the book would show as never started no matter how many
      // times it was read to the end.
      if (stopped && _lastState != u.state) {
        unawaited(_save(force: u.state == PlaybackState.finished));
      }

      // The rest of the tree reads the index in exactly two places — the
      // progress bar and the chapter panel's highlight — and both sit behind
      // `showControls`, which is false only while playing. The panel cannot
      // be open then either, because opening it pauses. So one word
      // replacing another mid-stream changes nothing that is on screen.
      //
      // The test is on both states rather than on the transition: a rewind
      // while paused emits without changing state, and the progress bar has
      // to follow it. Under elicited pacing every token emits
      // `awaitingAdvance`, so every token rebuilds — which is right, since
      // the controls are visible throughout that mode.
      final playingThroughout =
          u.state == PlaybackState.playing &&
          _lastState == PlaybackState.playing;

      // The offer is about the moment before reading starts. Once the
      // reader has moved at all they have either taken it or answered it.
      final offer =
          _offerFrontMatter && u.index == widget.book.contentStartIndex;

      _lastState = u.state;

      if (playingThroughout && offer == _offerFrontMatter) return;

      setState(() => _offerFrontMatter = offer);
    });

    _saveTimer = Timer.periodic(_saveInterval, (_) => unawaited(_save()));

    // Playback kept running behind a backgrounded app or a switched browser
    // tab, carrying the reader past text they never saw. That was merely
    // annoying until this screen started writing the place down.
    _lifecycle = AppLifecycleListener(onHide: _onHide, onPause: _onHide);

    _restoreProfile();
  }

  Future<void> _restoreProfile() async {
    final profile = await widget.repository.activeProfile();
    if (!mounted || profile.id == _profile.id) return;

    setState(() {
      _profile = profile;
      _session.profile = profile;
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _lifecycle?.dispose();
    _sub?.cancel();
    _session.dispose();
    _current.dispose();
    super.dispose();
  }

  ReadingResult? get _result {
    final locator = widget.book.text.locatorAt(_session.index);
    if (locator == null) return null;

    return ReadingResult(locator: locator, tokenIndex: _session.index);
  }

  /// Writes the current place, if it is not the one already written.
  ///
  /// The index is claimed before the await so an overlapping tick cannot
  /// issue the same write twice, and released again on failure so a later
  /// attempt still tries. A failed position write is not reported: the reader
  /// is mid-chapter, the outbox is intact, and there is nothing useful for
  /// them to do about it.
  ///
  /// [force] skips the "unchanged, nothing to save" check. Only the
  /// transition into [PlaybackState.finished] passes it — see the call site.
  Future<void> _save({bool force = false}) async {
    final result = _result;
    if (result == null) return;
    if (!force && result.tokenIndex == _lastSavedIndex) return;

    final previous = _lastSavedIndex;
    _lastSavedIndex = result.tokenIndex;

    try {
      await widget.onSave(result);
    } catch (_) {
      _lastSavedIndex = previous;
    }
  }

  void _onHide() {
    _session.pause();
    unawaited(_save());
  }

  List<Chapter> get _chapters => widget.book.chapters;

  bool get _drawerOpen => _scaffoldKey.currentState?.isDrawerOpen ?? false;

  void _toggle() {
    if (_session.state == PlaybackState.playing ||
        _session.state == PlaybackState.awaitingAdvance) {
      _session.pause();
    } else {
      _session.play();
    }
  }

  void _onSurfaceTap() {
    // The scrim swallows taps on the surface, but not key presses: the
    // shortcuts are bound above the Scaffold and stay live while the panel
    // is open. Advancing a word the reader cannot see, because they are
    // choosing a chapter, is not what either key meant.
    if (_drawerOpen) return;

    if (_session.state == PlaybackState.awaitingAdvance) {
      _session.advance();
    } else {
      _toggle();
    }
  }

  /// Runs [action] only while the reading surface has the reader's attention.
  void _whenReading(VoidCallback action) {
    if (_drawerOpen) return;
    action();
  }

  /// Opens the chapter panel.
  ///
  /// Pauses first, as switching profile does. Leaving the stream running
  /// behind the panel would have the reader return to a paragraph they never
  /// saw, and the position saved on close would be that one.
  void _openChapters() {
    if (_chapters.isEmpty) return;

    _session.pause();
    _scaffoldKey.currentState?.openDrawer();
  }

  /// Jumps to a chapter and leaves the session paused there.
  ///
  /// [PlaybackSession.seekToIndex] pauses unless already playing, and it is
  /// always paused here because opening the panel paused it. Landing mid
  /// flight at 250 wpm in a place the reader has not seen would mean the
  /// first words of the chapter go past before they have looked up.
  void _goToChapter(Chapter chapter) {
    _scaffoldKey.currentState?.closeDrawer();
    _session.seekToIndex(chapter.tokenIndex);
  }

  /// Takes the reader to the very start of the file, front matter included.
  ///
  /// Index 0 rather than a step backwards. The offer exists because the app
  /// does not know where the text begins, so guessing how far back to go
  /// would compound the first guess with a second. The start of the file is
  /// the one position that is certainly right.
  void _goToFrontMatter() => _session.seekToIndex(0);

  /// Escape and the system back gesture close the panel before they close
  /// the book.
  ///
  /// The route sets `canPop: false` so it can return a result, which means
  /// the drawer's own back handling never runs: `ModalRoute` reports
  /// `doNotPop` before the local history entry the drawer registers is
  /// consulted. Without this, backing out of the chapter list would exit the
  /// book.
  void _closeOrDismiss() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
      return;
    }
    unawaited(_close());
  }

  /// Switches profile mid-book.
  ///
  /// Lists what is actually on this device rather than the built-in presets
  /// alone, so a profile made in settings or synced from another device can
  /// be chosen here. Making and editing profiles lives in settings; this is
  /// only a switcher.
  Future<void> _pickProfile() async {
    _session.pause();

    final source = AppChromeSource.of(context);
    final chrome = readerChromeTheme(
      // This `context` sits above the `Theme` that `build` installs, so its
      // brightness is the app's own. Reading the reader's own theme here
      // would feed a brightness this screen just resolved back into the
      // resolution that produced it.
      presentation: resolvePresentation(
        _profile.presentation,
        Theme.of(context).brightness,
      ),
      accent: source.accent,
      highContrast: source.highContrast,
    );
    // The sheet's own container is themed here rather than in the builder.
    //
    // `showModalBottomSheet` reads `backgroundColor`, `shape`, `elevation`
    // and `surfaceTintColor` off `Theme.of(context)` at this call site, and
    // this context sits above the reader's own `Theme`. Wrapping the builder
    // reaches the rows inside the sheet and nothing else, so the panel came
    // up in the app's brightness carrying contents in the profile's, and the
    // two disagreed wherever a reader's theme and their background did.
    //
    // Read off `chrome.bottomSheetTheme` rather than written out again, so
    // `readerChromeTheme` stays the one place these are decided.
    final sheet = chrome.bottomSheetTheme;

    final chosen = await showModalBottomSheet<ReadingProfile>(
      context: context,
      backgroundColor: sheet.backgroundColor,
      elevation: sheet.elevation,
      shape: sheet.shape,
      // No `surfaceTintColor` here: `BottomSheetThemeData` carries one and
      // `showModalBottomSheet` takes no parameter for it. Nothing is lost.
      // `Material` applies a surface tint through `ElevationOverlay`, which
      // returns the colour unchanged at elevation 0, and `sheet.elevation`
      // is 0 for the reason every other panel in this app is.
      builder: (_) => Theme(
        data: chrome,
        child: SafeArea(
          child: StreamBuilder<List<ReadingProfile>>(
            stream: widget.repository.watchProfiles(),
            builder: (context, snapshot) {
              final profiles = snapshot.data;
              if (profiles == null) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              return ListView(
                shrinkWrap: true,
                children: [
                  for (final profile in profiles)
                    ListTile(
                      title: Text(profile.name),
                      subtitle: Text(describeProfile(profile)),
                      selected: profile.id == _profile.id,
                      onTap: () => Navigator.of(context).pop(profile),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );

    if (chosen == null || !mounted) return;

    setState(() {
      _profile = chosen;
      _session.profile = chosen;
    });

    // Remembered on this device only. Which profile is in use is not synced:
    // a phone read outdoors and a desktop in a dim room can want different
    // ones, and a shared pointer would have each undo the other.
    await widget.repository.setActiveProfile(
      chosen.id,
      hlc: await widget.issueStamp(),
    );
  }

  /// Stops, records the place, and leaves.
  ///
  /// The write is awaited before popping. The library syncs on return, and
  /// draining an outbox that has not been written to yet would send the
  /// previous position and call it current.
  Future<void> _close() async {
    final navigator = Navigator.of(context);

    _session.pause();
    await _save();

    if (mounted) navigator.pop();
  }

  /// Which chapter the reader is inside: the last one that starts at or
  /// before the current token. -1 before the first chapter begins, which is
  /// where front matter sits.
  int get _currentChapter {
    var found = -1;
    for (var i = 0; i < _chapters.length; i++) {
      if (_chapters[i].tokenIndex > _session.index) break;
      found = i;
    }
    return found;
  }

  /// What tapping the surface does right now, for a screen reader.
  ///
  /// The surface is the app's primary control — play, pause, and advance
  /// under elicited pacing — and was a bare `GestureDetector` with no role
  /// and no label, so TalkBack found nothing on it at all.
  String get _surfaceLabel => switch (_session.state) {
    PlaybackState.playing => 'Pause reading',
    PlaybackState.awaitingAdvance => 'Next word',
    PlaybackState.finished => 'End of book',
    _ => 'Start reading',
  };

  @override
  Widget build(BuildContext context) {
    final state = _session.state;
    final showControls = state != PlaybackState.playing;

    // The reader's accent and contrast choices, taken from the app theme
    // above this route. `buildScheme` folds both into every role and cannot
    // report either back, so `appTheme` carries them separately. See
    // [AppChromeSource].
    final source = AppChromeSource.of(context);

    // The one place this screen decides a polarity, and everything below
    // takes the answer rather than asking again. A profile that names one
    // keeps it; a profile that leaves it open takes the brightness the app
    // is already in, which is read here rather than from the `Theme` this
    // method installs a few lines down. See ADR 0016.
    final presentation = resolvePresentation(
      _profile.presentation,
      Theme.of(context).brightness,
    );

    final ink = colorOf(readerInkArgbFor(presentation));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeOrDismiss();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): _onSurfaceTap,
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _whenReading(_session.advance),
          // The only rewind left. ADR 0015 took the button off the surface
          // ahead of the tap zones, and a reader on a keyboard or a switch
          // has no tap zone to reach for in the meantime.
          //
          // Steps by the profile's own `rewindWords` rather than the five
          // the button passed. That field already decides how far a resume
          // steps back, and two numbers for one idea is how they drift.
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _whenReading(() => _session.rewind(_profile.rewindWords)),
          const SingleActivator(LogicalKeyboardKey.keyC): _openChapters,
          const SingleActivator(LogicalKeyboardKey.escape): _closeOrDismiss,
        },
        child: Focus(
          autofocus: true,
          // Everything below is drawn on the reading surface, so it follows
          // the profile rather than the platform. Above the Scaffold so the
          // chapter panel is included: it opens over the same surface.
          child: Theme(
            data: readerChromeTheme(
              presentation: presentation,
              accent: source.accent,
              highContrast: source.highContrast,
            ),
            child: Scaffold(
              key: _scaffoldKey,
              // No drawer at all when the book declares no chapters, so the
              // edge of the screen does nothing rather than opening an empty
              // panel.
              drawer: _chapters.isEmpty
                  ? null
                  : _ChapterPanel(
                      bookTitle: widget.book.title,
                      chapters: _chapters,
                      currentIndex: _currentChapter,
                      onSelected: _goToChapter,
                    ),
              // The whole surface is a tap target, and an edge drag is easy
              // to start by accident on a phone. Opening a panel mid-sentence
              // that way would be the app interrupting the reader.
              drawerEnableOpenDragGesture: false,
              body: GestureDetector(
                onTap: _onSurfaceTap,
                behavior: HitTestBehavior.opaque,
                // The semantics for this tap live on the reading surface
                // below, which is what the gesture is actually for. Left on
                // here, the detector reports a single tappable region
                // covering the whole screen, controls included.
                excludeFromSemantics: true,
                child: Stack(
                  children: [
                    Positioned.fill(
                      // The only subtree that rebuilds per word. Everything
                      // else in this Stack is invariant while playing.
                      child: ValueListenableBuilder<PlaybackUpdate?>(
                        valueListenable: _current,
                        builder: (_, update, _) => Semantics(
                          button: true,
                          // Replaces the word's own semantics rather than
                          // adding to them: the surface is one control, and
                          // a word announced separately from the button
                          // would make it two.
                          excludeSemantics: true,
                          label: _surfaceLabel,
                          // Offered only while the stream is stopped. A
                          // reader using RSVP is reading with their eyes,
                          // and speech four times a second would fight that
                          // rather than serve it — anyone who needs speech
                          // instead of sight is better served by the whole
                          // book read aloud than by one word at a time.
                          // Paused, advanced or rewound, the word on screen
                          // is one fact worth having on focus, and each of
                          // those is something the reader just did.
                          value: state == PlaybackState.playing
                              ? ''
                              : (update?.token?.text ?? ''),
                          onTap: _onSurfaceTap,
                          child: RsvpView(
                            update: update,
                            presentation: presentation,
                          ),
                        ),
                      ),
                    ),
                    if (state == PlaybackState.finished)
                      Center(
                        child: Text(
                          'End of book',
                          style: TextStyle(color: ink),
                        ),
                      ),
                    if (showControls && _chapters.isNotEmpty)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            // A bare glyph in the surface's own ink. The
                            // filled tonal disc this replaced took
                            // `secondaryContainer`, which is an accent role,
                            // so it drew a coloured circle over a background
                            // the reader had chosen.
                            //
                            // `Icons.menu` rather than `menu_book_outlined`:
                            // the book glyph is what the Library tab uses in
                            // `app_shell.dart`, and the same picture meaning
                            // "your books" in one place and "this book's
                            // chapters" in another is a picture meaning two
                            // things.
                            child: IconButton(
                              onPressed: _openChapters,
                              iconSize: _secondaryIconSize,
                              color: ink,
                              icon: const Icon(Icons.menu),
                              tooltip: 'Chapters',
                            ),
                          ),
                        ),
                      ),
                    if (showControls)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_offerFrontMatter)
                              _FrontMatterOffer(
                                onAccept: _goToFrontMatter,
                                onDismiss: () =>
                                    setState(() => _offerFrontMatter = false),
                              ),
                            _Controls(
                              state: state,
                              progress: widget.book.text.progressAt(
                                _session.index,
                              ),
                              presentation: presentation,
                              onClose: _closeOrDismiss,
                              onToggle: _toggle,
                              onProfile: _pickProfile,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The book's own table of contents, as a panel.
///
/// Read-only and flat. Depth is shown as indentation rather than as
/// collapsible sections: a reader looking for Act III Scene II wants to see
/// it, not to expand Act III first.
class _ChapterPanel extends StatelessWidget {
  final String bookTitle;
  final List<Chapter> chapters;
  final int currentIndex;
  final ValueChanged<Chapter> onSelected;

  const _ChapterPanel({
    required this.bookTitle,
    required this.chapters,
    required this.currentIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bookTitle, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'From this book’s own table of contents',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: chapters.length,
                itemBuilder: (context, i) {
                  final chapter = chapters[i];

                  return ListTile(
                    // Indentation carries the nesting. Capped so a deeply
                    // nested book does not push its titles off the panel.
                    contentPadding: EdgeInsets.only(
                      left: 16.0 + 16.0 * chapter.depth.clamp(0, 3),
                      right: 16,
                    ),
                    title: Text(
                      chapter.title,
                      style: chapter.depth == 0
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.bodyMedium,
                    ),
                    selected: i == currentIndex,
                    onTap: () => onSelected(chapter),
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

/// Says the opening position was a guess, and offers the start of the file.
///
/// Above the controls rather than over the text: it is a note about the book
/// rather than part of it, and the reading surface is a tap target that a
/// button sitting on it would compete with.
///
/// A panel rather than a control, so it takes a surface role from the ramp
/// and reads at 4.5:1 against it. It sat on `secondaryContainer` until ADR
/// 0015, which is an accent role, so the one place on this screen carrying a
/// paragraph of text was also the largest block of colour on it.
class _FrontMatterOffer extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const _FrontMatterOffer({required this.onAccept, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hairline = theme.dividerTheme.thickness ?? AppHairline.width;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        // The panel sits on the reader's own background, which the ramp
        // knows nothing about, so it needs an edge of its own to separate
        // the two.
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: hairline),
          bottom: BorderSide(color: scheme.outlineVariant, width: hairline),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This opened past what looked like a title and licence page. '
            'That was a guess, and nothing was removed.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onDismiss,
                child: const Text('Carry on here'),
              ),
              TextButton(
                onPressed: onAccept,
                child: const Text('Start at the beginning'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Icon sizes on the reading surface.
///
/// Hierarchy is carried by size because it can no longer be carried by
/// colour. Everything here is one ink on the reader's own background, so
/// play has to look like the primary action without being a different
/// colour from exit and profile. 44 against 28 does that; a filled shape
/// would put a second block of colour on a screen whose colours the reader
/// chose.
///
/// Both sit inside `IconButton`'s own 48dp minimum, so neither changes the
/// tap target.
const double _primaryIconSize = 44;
const double _secondaryIconSize = 28;

/// Exit, play and profile, over a progress bar.
///
/// Three buttons rather than four. Rewind moved to the arrow key in ADR
/// 0015 and comes back as a left-side tap zone, which is a change to what
/// the reading surface itself does rather than another glyph in this row.
///
/// [ink] is resolved once by the reader screen from the profile's own
/// background, rather than read from the theme here. The panels this screen
/// opens take the neutral ramp and this row does not: it sits on whatever
/// the reader picked in the background field, which the ramp knows nothing
/// about.
/// Exit, play and profile, over a progress bar.
///
/// Three buttons rather than four. Rewind moved to the arrow key in ADR
/// 0015 and comes back as a left-side tap zone, which is a change to what
/// the reading surface itself does rather than another glyph in this row.
///
/// Takes the profile rather than a resolved colour. The row needs three
/// colours that all derive from the background, and passing one in while
/// deriving the others here would put half the answer in the caller.
class _Controls extends StatelessWidget {
  final PlaybackState state;
  final double progress;
  final ResolvedPresentation presentation;
  final VoidCallback onClose;
  final VoidCallback onToggle;
  final VoidCallback onProfile;

  const _Controls({
    required this.state,
    required this.progress,
    required this.presentation,
    required this.onClose,
    required this.onToggle,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final ink = colorOf(readerInkArgbFor(presentation));

    // `_toggle` pauses from `awaitingAdvance` as well as from `playing`, so
    // both states show the glyph for what the button does. The old row read
    // its icon off `playing` alone and offered a play glyph under elicited
    // pacing on a button that pauses.
    final stopping =
        state == PlaybackState.playing ||
        state == PlaybackState.awaitingAdvance;

    // What tapping the button does. `_surfaceLabel` says what tapping the
    // surface does, and under elicited pacing those differ.
    final toggleLabel = switch (state) {
      PlaybackState.playing => 'Pause',
      PlaybackState.awaitingAdvance => 'Stop advancing',
      PlaybackState.finished => 'Read again',
      _ => 'Read',
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The one accent on this screen, where the accent survives the
            // reader's background. `readerProgressFillFor` drops to the ink
            // on the backgrounds that cannot support one.
            //
            // Height is twice the radius, which is what makes the ends
            // semicircular rather than merely rounded. Both colours come
            // from the profile rather than from a scheme surface role: the
            // ramp does not know what is behind this bar.
            LinearProgressIndicator(
              value: progress,
              minHeight: AppRadii.sm * 2,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              color: readerProgressFillFor(
                scheme: Theme.of(context).colorScheme,
                presentation: presentation,
              ),
              backgroundColor: readerTrackFor(presentation),
              semanticsLabel: 'Progress through the book',
              semanticsValue: '${(progress * 100).round()}%',
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: onClose,
                  iconSize: _secondaryIconSize,
                  color: ink,
                  icon: const Icon(Icons.close),
                  tooltip: 'Back to library',
                ),
                IconButton(
                  key: readerPlayButtonKey,
                  onPressed: onToggle,
                  iconSize: _primaryIconSize,
                  color: ink,
                  icon: Icon(stopping ? Icons.pause : Icons.play_arrow),
                  tooltip: toggleLabel,
                ),
                IconButton(
                  onPressed: onProfile,
                  iconSize: _secondaryIconSize,
                  color: ink,
                  icon: const Icon(Icons.tune),
                  tooltip: 'Reading profile',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
