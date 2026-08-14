import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import 'library_book.dart';
import 'profile_presentation.dart';
import 'rsvp_view.dart';

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
  /// without a transaction, so a paused reader writes nothing at all.
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
      if (stopped && _lastState != u.state) unawaited(_save());

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
  Future<void> _save() async {
    final result = _result;
    if (result == null || result.tokenIndex == _lastSavedIndex) return;

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
  /// Switches profile mid-book.
  ///
  /// Lists what is actually on this device rather than the built-in presets
  /// alone, so a profile made in settings or synced from another device can
  /// be chosen here. Making and editing profiles lives in settings; this is
  /// only a switcher.
  Future<void> _pickProfile() async {
    _session.pause();

    final chosen = await showModalBottomSheet<ReadingProfile>(
      context: context,
      // A modal route is inserted at the Navigator, not below the widget
      // that opened it, so it does not inherit the reader's chrome theme
      // from the tree. Applied again here, because this sheet slides up over
      // the reading surface and a light one over a dark surface is the
      // problem this whole change exists to fix.
      builder: (_) => Theme(
        data: readerChromeTheme(_profile.presentation),
        child: SafeArea(
          child: StreamBuilder<List<ReadingProfile>>(
            stream: widget.repository.watchProfiles(),
            builder: (context, snapshot) {
              final profiles = snapshot.data;
              if (profiles == null) {
                return const Padding(
                  padding: EdgeInsets.all(32),
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
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _whenReading(_session.rewind),
          const SingleActivator(LogicalKeyboardKey.keyC): _openChapters,
          const SingleActivator(LogicalKeyboardKey.escape): _closeOrDismiss,
        },
        child: Focus(
          autofocus: true,
          // Everything below is drawn on the reading surface, so it follows
          // the profile rather than the platform. Above the Scaffold so the
          // chapter panel is included: it opens over the same surface.
          child: Theme(
            data: readerChromeTheme(_profile.presentation),
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
                            presentation: _profile.presentation,
                          ),
                        ),
                      ),
                    ),
                    if (state == PlaybackState.finished)
                      const Center(child: Text('End of book')),
                    if (showControls && _chapters.isNotEmpty)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: IconButton.filledTonal(
                              onPressed: _openChapters,
                              iconSize: 32,
                              icon: const Icon(Icons.menu_book_outlined),
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
                              onClose: _closeOrDismiss,
                              onRewind: () => _session.rewind(5),
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
/// Deliberately plain — theme colours and two text buttons. What matters here
/// is when it appears and where it sends the reader; the chrome is expected
/// to be replaced.
class _FrontMatterOffer extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const _FrontMatterOffer({required this.onAccept, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This opened past what looked like a title and licence page. '
            'That was a guess, and nothing was removed.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
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

class _Controls extends StatelessWidget {
  final PlaybackState state;
  final double progress;
  final VoidCallback onClose;
  final VoidCallback onRewind;
  final VoidCallback onToggle;
  final VoidCallback onProfile;

  const _Controls({
    required this.state,
    required this.progress,
    required this.onClose,
    required this.onRewind,
    required this.onToggle,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      PlaybackState.awaitingAdvance => 'Tap to advance',
      PlaybackState.finished => 'Done',
      _ => 'Read',
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: progress,
              semanticsLabel: 'Progress through the book',
              semanticsValue: '${(progress * 100).round()}%',
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton.filledTonal(
                  onPressed: onClose,
                  iconSize: 32,
                  icon: const Icon(Icons.close),
                  tooltip: 'Back to library',
                ),
                IconButton.filledTonal(
                  onPressed: onRewind,
                  iconSize: 32,
                  icon: const Icon(Icons.replay_5),
                  tooltip: 'Back five words',
                ),
                FilledButton.icon(
                  onPressed: onToggle,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(160, 56),
                  ),
                  icon: Icon(
                    state == PlaybackState.playing
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  label: Text(label),
                ),
                IconButton.filledTonal(
                  onPressed: onProfile,
                  iconSize: 32,
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
