import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'library_book.dart';
import 'mode_fork.dart';
import 'profile_actions.dart';
import 'profile_edit_screen.dart';
import 'profile_presentation.dart';
import 'profile_row.dart';
import 'profiles_screen.dart';
import 'reading_display.dart';
import 'reading_surface.dart';
import 'scroll_clock.dart';

/// Identifies the play and pause button on the reading surface.
///
/// The button carried a text label until ADR 0015, and five tests across
/// `reader_progress_test.dart` and `reader_semantics_test.dart` reached it
/// with `find.text('Read')`. Each of those was asserting two things: that
/// playback starts, and that the control says a particular word. A key
/// asserts the first alone, as `homeContinueTileKey` and `appNavBarKey`
/// already do for Home and the shell.
const Key readerPlayButtonKey = Key('reader-play-button');

/// Opens the reader's profile sheet — switching, editing, and the route to
/// the full profiles screen. Keyed for the same reason as
/// [readerPlayButtonKey].
const Key readerProfileButtonKey = Key('reader-profile-button');

/// The three regions the reading surface is divided into.
///
/// Left and right step by the reader's configured amount and stop; the centre
/// keeps every job the whole surface used to have. Keys rather than labels for
/// the same reason [readerPlayButtonKey] exists — and more so here, because
/// the left and right labels name a number that changes with a setting. See
/// ADR 0020.
const Key readerTapBackKey = Key('reader-tap-back');
const Key readerTapCentreKey = Key('reader-tap-centre');
const Key readerTapForwardKey = Key('reader-tap-forward');

/// The single region continuous scroll replaces the three zones with.
///
/// One surface rather than three, because the zones are a fixed-anchor
/// arrangement: under scroll the reader drags to where they want to be and a
/// tap anywhere starts or stops. See ADR 0025.
const Key readerScrollSurfaceKey = Key('reader-scroll-surface');

/// The presentation mode switch in the reader's profile sheet.
const Key readerScrollModeKey = Key('reader-scroll-mode');

/// The four sentence and paragraph jumps in the nav row. See ADR 0021.
const Key readerSentenceButtonKey = Key('reader-sentence-button');
const Key readerParagraphButtonKey = Key('reader-paragraph-button');
const Key readerBackSentenceButtonKey = Key('reader-back-sentence-button');
const Key readerBackParagraphButtonKey = Key('reader-back-paragraph-button');

/// Where the reader stopped.
///
/// The token index travels alongside the locator because the service has no
/// copy of the book and cannot work out how far apart two positions are
/// without it. The locator remains the authoritative position; this is only
/// a hint for judging divergence.
///
/// The chapter is a second hint, and a narrower one: it describes this
/// device's parse of this copy of the book and never leaves the device. See
/// ADR 0018.
class ReadingResult {
  final Locator locator;
  final int tokenIndex;

  /// The chapter this position is in, as the book itself names it.
  ///
  /// Null in front matter, and null for any book that declares no table of
  /// contents — a note, or an EPUB carrying neither a navigation document nor
  /// an NCX. Those readers get a figure with no chapter beside it rather than
  /// a guessed one: ADR 0010's argument, in the place it reaches next.
  final String? chapterTitle;

  /// The token that chapter ends before, exclusive.
  ///
  /// Null exactly when [chapterTitle] is. Carried rather than a chapter
  /// index, because the screens that read it hold no table of contents to
  /// index into — the whole reason this is stored at all.
  final int? chapterEndIndex;

  const ReadingResult({
    required this.locator,
    required this.tokenIndex,
    this.chapterTitle,
    this.chapterEndIndex,
  });
}

/// What tapping a row or an overflow item in the reader's profile sheet
/// means.
///
/// The sheet used to pop a bare [ReadingProfile] meaning "select this one".
/// It now offers edit, copy, delete and a route to the full profiles screen
/// too, and a bottom sheet is the wrong place to run a confirm dialog or push
/// a route — so it only reports intent, and [_ReaderScreenState._pickProfile]
/// acts on it after the sheet has closed.
sealed class _ProfileIntent {
  const _ProfileIntent();
}

class _SelectProfile extends _ProfileIntent {
  final ReadingProfile profile;
  const _SelectProfile(this.profile);
}

class _EditProfile extends _ProfileIntent {
  final ReadingProfile profile;
  const _EditProfile(this.profile);
}

class _CopyProfile extends _ProfileIntent {
  final ReadingProfile profile;
  const _CopyProfile(this.profile);
}

class _DeleteProfile extends _ProfileIntent {
  final ReadingProfile profile;
  const _DeleteProfile(this.profile);
}

class _ManageProfiles extends _ProfileIntent {
  const _ManageProfiles();
}

/// Switch the *active* profile's presentation mode, from the reader.
///
/// The mode is the one reading setting a reader plausibly wants to change
/// with a book open — a chapter of dense prose reads differently one word at
/// a time than sliding — and reaching it otherwise means the editor, two
/// screens away. See ADR 0025.
///
/// Carries [profiles] rather than letting the screen query them back. The
/// sheet is already built on a stream of every profile, so the list is in
/// scope at the moment the switch is tapped; riding it along here is what
/// lets [_ReaderScreenState._setMode] decide without an await between
/// binding the active profile and deciding its fate.
class _SetMode extends _ProfileIntent {
  final PresentationMode mode;
  final List<ReadingProfile> profiles;
  const _SetMode(this.mode, this.profiles);
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

class _ReaderScreenState extends State<ReaderScreen>
    with SingleTickerProviderStateMixin {
  late final PlaybackSession _session;

  /// Time and geometry for continuous scroll. Built whatever the mode is,
  /// because the mode can change mid-book from the profile sheet, and inert
  /// until a scrolling profile arrives.
  late final ScrollClock _clock;

  /// Whether the surface was playing when the finger landed.
  ///
  /// The pointer-down pauses before the tap is arbitrated, so by the time
  /// `onTap` fires the answer is already gone. See [_grabSurface].
  bool _wasPlayingAtDown = false;
  StreamSubscription<PlaybackUpdate>? _sub;

  /// The same subscription Home, Library and the full profiles screen hold:
  /// a pointer in `preferences` naming a row in `stored_profiles`, so a
  /// change written anywhere — a route this sheet pushes, another screen,
  /// another device, a background sync — reaches [_profile] and the session
  /// without this screen reloading anything by hand.
  StreamSubscription<ReadingProfile>? _profileSub;

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

  /// How far one tap on an edge zone, or one arrow key, moves.
  ///
  /// Read from the preference the same way [_profile] is read from the
  /// database, and for the same reason: the session is built synchronously
  /// and a reader can tap before the read returns.
  ///
  /// A plain read rather than a `ReadingDisplayController` threaded down from
  /// the shell. Home and Library listen to one because they stay alive in the
  /// cross-fading stack while Settings changes underneath them; this route is
  /// pushed above the shell and torn down on exit, so the value cannot go
  /// stale while a book is open. Threading a controller through `BookOpener`
  /// is also what ADR 0015 rejected for `AppearanceController`.
  int _stepWords = kDefaultStepWords;

  late final ProfileActions _profileActions;

  @override
  void initState() {
    super.initState();
    _profileActions = ProfileActions(
      repository: widget.repository,
      issueStamp: widget.issueStamp,
    );
    _session = PlaybackSession(
      tokens: widget.book.text.tokens,
      profile: _profile,
      startIndex: widget.book.resumeIndex,
    );

    _clock = ScrollClock(
      session: _session,
      vsync: this,
      tokens: widget.book.text.tokens,
      isParagraphEnd: widget.book.text.isParagraphEndAt,
      chapterStarts: {for (final c in _chapters) c.tokenIndex},
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

      // Idempotent and cheap. Starts and stops the ticker with the state,
      // and moves the measured window when the anchor nears its edge —
      // neither of which goes through `setState`, so the early return below
      // still holds while scrolling.
      _clock.sync();

      final stopped =
          u.state == PlaybackState.paused || u.state == PlaybackState.finished;

      // On the transition rather than on every update, so the second emit
      // a chapter jump's `stopAt` produces does not queue a second write.
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

    // The fact is pushed rather than fetched: this is the one place the
    // screen's copy of the active profile changes, whether the write came
    // from this sheet, another screen, or another device. `_profile` opens
    // on `Presets.standard` above and is swapped in here as soon as the
    // stored choice loads, unconditionally — the profile already in use can
    // be edited without its id moving, and that edit has to reach the
    // session too.
    _profileSub = widget.repository.watchActiveProfile().listen((profile) {
      if (!mounted) return;

      setState(() {
        _profile = profile;
        _session.profile = profile;
      });
      _syncClock();
    });

    _restoreStep();
  }

  /// The profile's presentation with its polarity decided.
  ///
  /// One expression, read by `build` and by the scroll clock. Two of these
  /// could disagree about the polarity, and the marquee would then be
  /// measured in one ink and painted in another.
  ResolvedPresentation get _presentation =>
      resolvePresentation(_profile.presentation, Theme.of(context).brightness);

  /// Hands the clock the presentation it measures under.
  ///
  /// Never from `build`: this can replace the measured window, and marking a
  /// painter dirty from inside a build is not something to reason about once
  /// a frame.
  void _syncClock() {
    if (!mounted) return;
    _clock.applyPresentation(_presentation);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncClock();
  }

  Future<void> _restoreStep() async {
    final stored = await widget.repository.preference(
      ReadingDisplayKeys.stepWords,
    );
    final step = decodeStepWords(stored);
    if (!mounted || step == _stepWords) return;

    // Through setState because the zones announce the number to a screen
    // reader, so it is drawn as well as acted on.
    setState(() => _stepWords = step);
  }

  /// Back and forward by [_stepWords], stopping where they land.
  ///
  /// `stopAt` rather than `rewind` and `advance`: a step is a place the reader
  /// picked, and resuming from it must not step back again by the profile's
  /// `rewindWords`. Under a tap zone those two land one after the other on
  /// every press. See ADR 0020.
  void _stepBack() => _session.stopAt(_session.index - _stepWords);

  void _stepForward() => _session.stopAt(_session.index + _stepWords);

  /// The next sentence and the next paragraph, or null where there is none.
  ///
  /// Null rather than a clamp, so the control is absent rather than present
  /// and inert at the end of the book. Read in `build`, which runs only while
  /// the controls are visible and so never on the reading path.
  int? get _nextSentence => widget.book.text.nextSentenceStart(_session.index);

  int? get _nextParagraph =>
      widget.book.text.nextParagraphStart(_session.index);

  /// The previous sentence and paragraph, or null where there is none.
  ///
  /// Each restarts the unit the reader is in rather than always leaving it:
  /// mid-sentence lands on that sentence's own first word, and only a second
  /// press — already on a sentence's first word — reaches the one before.
  /// See ADR 0021.
  int? get _previousSentence =>
      widget.book.text.previousSentenceStart(_session.index);

  int? get _previousParagraph =>
      widget.book.text.previousParagraphStart(_session.index);

  /// A callback that lands on [target], or null when there is no target.
  ///
  /// Through `stopAt` like the edge zones, so all six navigation controls
  /// leave the reader stopped on a word they chose and resume from it.
  VoidCallback? _jumpTo(int? target) =>
      target == null ? null : () => _whenReading(() => _session.stopAt(target));

  @override
  void dispose() {
    _saveTimer?.cancel();
    _lifecycle?.dispose();
    _sub?.cancel();
    // Cancelled before the session and the clock it feeds are torn down, so
    // a late emission from the stream cannot reach either after they are
    // gone.
    _profileSub?.cancel();
    _clock.dispose();
    _session.dispose();
    _current.dispose();
    super.dispose();
  }

  ReadingResult? get _result {
    final locator = widget.book.text.locatorAt(_session.index);
    if (locator == null) return null;

    // Resolved here rather than by whatever screen displays it. This is the
    // only place in the app holding both a parsed table of contents and a
    // token index, and it holds them together for the length of one sitting.
    final at = _currentChapter;
    final chapter = at < 0 ? null : _chapters[at];

    return ReadingResult(
      locator: locator,
      tokenIndex: _session.index,
      chapterTitle: chapter?.title,
      chapterEndIndex: chapter == null
          ? null
          : chapterEndAt(_chapters, at, widget.book.text.length),
    );
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

  /// The finger has landed on a scrolling surface.
  ///
  /// Pauses immediately, from a raw `Listener` rather than `onTapDown`:
  /// `BaseTapGestureRecognizer` defers that callback until it wins the arena,
  /// the pointer lifts, or `kPressTimeout` — 100 ms, which at 250 wpm is
  /// most of a word of text still sliding past after the reader has touched
  /// the screen to stop it. A `Listener` never joins the arena, so it takes
  /// nothing from the detector beneath it.
  ///
  /// Records what it interrupted, because `onTap` fires afterwards and by
  /// then the state it needs to branch on has already been changed here.
  void _grabSurface() {
    if (_drawerOpen) return;

    _wasPlayingAtDown = _session.state == PlaybackState.playing;
    _session.pause();
  }

  /// The finger has lifted off a drag, or the pointer was cancelled.
  ///
  /// `stopHere` rather than `stopAt`: the reader let go at a particular place
  /// in a particular word, and `stopAt` would zero the sub-token offset and
  /// snap the text by up to a word at the moment of release. It also arms the
  /// one-shot rewind suppression, so pressing play does not undo the scrub —
  /// ADR 0022's guarantee, reached from a drag instead of a jump.
  void _releaseSurface() {
    if (_drawerOpen) return;
    _session.stopHere();
  }

  /// A tap that turned out not to be a drag.
  ///
  /// The pointer-down has already paused, so a tap on moving text has done
  /// its job by arriving. Only a tap that landed on stopped text starts it.
  void _scrollTap() {
    if (_drawerOpen || _wasPlayingAtDown) return;
    _session.play();
  }

  void _scrubSurface(double dx) {
    if (_drawerOpen) return;
    _session.scrubBy(dx);
  }

  /// A wheel or a trackpad.
  ///
  /// In scope rather than a nice-to-have: a [PointerSignalEvent] is not
  /// routed through the gesture arena, so no recognizer ever sees a wheel and
  /// scrolling would have been undraggable on two of the three platforms this
  /// ships to.
  void _onSurfaceSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (_drawerOpen || !_session.scrolling) return;

    _session.pause();
    _session.scrubBy(event.scrollDelta.dy);
    _session.stopHere();
  }

  /// The token [index] would land on, for a screen reader's step actions.
  String _wordAt(int index) {
    final tokens = widget.book.text.tokens;
    if (tokens.isEmpty) return '';
    return tokens[index.clamp(0, tokens.length - 1)].text;
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
  /// `stopAt` rather than `seekToIndex`: opening the panel already paused the
  /// session, and landing through `seekToIndex` left the next `play` free to
  /// apply `rewindWords` on the way out, putting the reader back in the
  /// chapter they just left. `stopAt` suppresses that one resume rewind, the
  /// same guarantee every other jump on this screen already carries. See
  /// ADR 0022.
  void _goToChapter(Chapter chapter) {
    _scaffoldKey.currentState?.closeDrawer();
    _session.stopAt(chapter.tokenIndex);
  }

  /// Takes the reader to the very start of the file, front matter included.
  ///
  /// Index 0 rather than a step backwards. The offer exists because the app
  /// does not know where the text begins, so guessing how far back to go
  /// would compound the first guess with a second. The start of the file is
  /// the one position that is certainly right.
  ///
  /// `stopAt`, not `seekToIndex`, for the same resume-rewind reason as
  /// `_goToChapter`.
  void _goToFrontMatter() => _session.stopAt(0);

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

  /// Switches profile mid-book, and now reaches everything else a reading
  /// profile can need without leaving the book: editing, copying, deleting,
  /// and the full profiles screen behind a "Reading profiles" row.
  ///
  /// Lists what is actually on this device rather than the built-in presets
  /// alone, so a profile made in settings or synced from another device can
  /// be chosen here.
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

    final intent = await showModalBottomSheet<_ProfileIntent>(
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
                    ProfileRow(
                      profile: profile,
                      selected: profile.id == _profile.id,
                      onSelect: () =>
                          Navigator.of(context).pop(_SelectProfile(profile)),
                      onEdit: () =>
                          Navigator.of(context).pop(_EditProfile(profile)),
                      onDuplicate: () =>
                          Navigator.of(context).pop(_CopyProfile(profile)),
                      onDelete: profile.isBuiltIn
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop(_DeleteProfile(profile)),
                    ),
                  const Divider(height: 1),
                  // Below the list rather than above it. The sheet is
                  // primarily the profile picker, and a tile at the top
                  // pushed the last profile out of a shrink-wrapped sheet's
                  // viewport — `reader_profile_menu_test.dart` counts them.
                  SwitchListTile(
                    key: readerScrollModeKey,
                    secondary: const Icon(AppIcons.sectionReading),
                    title: const Text('Sliding text'),
                    subtitle: const Text(
                      'One line moves past a fixed mark, instead of one word '
                      'at a time. Drag to move through the book.',
                    ),
                    value:
                        _profile.presentation.mode ==
                        PresentationMode.continuousScroll,
                    onChanged: (on) => Navigator.of(context).pop(
                      _SetMode(
                        on
                            ? PresentationMode.continuousScroll
                            : PresentationMode.fixedSingle,
                        profiles,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(AppIcons.sectionProfiles),
                    title: const Text('Reading profiles'),
                    onTap: () =>
                        Navigator.of(context).pop(const _ManageProfiles()),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    if (!mounted || intent == null) return;

    switch (intent) {
      case _SelectProfile(:final profile):
        // Remembered on this device only. Which profile is in use is not
        // synced: a phone read outdoors and a desktop in a dim room can want
        // different ones, and a shared pointer would have each undo the
        // other.
        //
        // A plain write: the subscription in `initState` delivers it back to
        // `_profile` and the session, the same way it delivers a change
        // written anywhere else.
        await widget.repository.setActiveProfile(
          profile.id,
          hlc: await widget.issueStamp(),
        );

      case _EditProfile(:final profile):
        final result = await Navigator.of(context).push<ReadingProfile>(
          MaterialPageRoute(
            builder: (_) => ProfileEditScreen(
              profile: profile,
              repository: widget.repository,
              issueStamp: widget.issueStamp,
            ),
          ),
        );
        if (!mounted) return;
        if (result != null && result.id != profile.id) {
          // The editor forked a preset. Same rule as ProfilesScreen: what
          // was just created is what the reader continues with. Writing the
          // pointer is enough; the subscription delivers the result, edited
          // or forked.
          await widget.repository.setActiveProfile(
            result.id,
            hlc: await widget.issueStamp(),
          );
        }

      case _CopyProfile(:final profile):
        // ProfileActions.duplicate writes the fork's own pointer; the
        // subscription picks it up without a reload here.
        await _profileActions.duplicate(context, profile);

      case _DeleteProfile(:final profile):
        // Deleting the active profile clears the pointer in the repository,
        // and the subscription resolves that back to Standard rather than a
        // dangling id.
        await _profileActions.delete(context, profile);

      case _SetMode(:final mode, :final profiles):
        await _setMode(mode, profiles);

      case _ManageProfiles():
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ProfilesScreen(
              repository: widget.repository,
              issueStamp: widget.issueStamp,
            ),
          ),
        );
    }
  }

  /// Puts the active profile into [mode], performing whatever [decideMode]
  /// says that takes, given the reader's other [profiles].
  ///
  /// Binds the active profile once, here, and passes only [profile] to
  /// [decideMode] — never `_profile` again. `_profile` is the reading
  /// screen's own copy, and once the active profile arrives on a stream an
  /// await inside this method is a point where that copy can move out from
  /// under it. Re-reading it after one of those awaits would let the wrong
  /// profile decide what to fork, or worse, what to delete. [decideMode]
  /// itself is synchronous, so binding [profile] and deciding its fate has
  /// no such gap between them; [profiles] arrives with the intent rather
  /// than through a query here for the same reason.
  ///
  /// This method only performs the writes [decideMode] describes — the
  /// `setState`, the session update and the mounted checks aside, it decides
  /// nothing. See ADR 0025 and `mode_fork.dart` for the policy.
  Future<void> _setMode(
    PresentationMode mode,
    List<ReadingProfile> profiles,
  ) async {
    final profile = _profile;
    final decision = decideMode(
      profile: profile,
      mode: mode,
      profiles: profiles,
    );

    switch (decision) {
      case ReturnToPreset(:final preset, :final discard):
        await widget.repository.setActiveProfile(
          preset.id,
          hlc: await widget.issueStamp(),
        );
        if (!mounted) return;

        if (discard != null) {
          await widget.repository.deleteProfile(
            discard.id,
            hlc: await widget.issueStamp(),
          );
        }

      case SelectExistingFork(:final fork):
        await widget.repository.setActiveProfile(
          fork.id,
          hlc: await widget.issueStamp(),
        );

      case SaveInPlace(:final profile):
        await widget.repository.saveProfile(
          profile,
          hlc: await widget.issueStamp(),
        );

      case ForkAndSelect(:final profile):
        await widget.repository.saveProfile(
          profile,
          hlc: await widget.issueStamp(),
        );
        if (!mounted) return;

        await widget.repository.setActiveProfile(
          profile.id,
          hlc: await widget.issueStamp(),
        );
    }
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

  /// Which chapter the reader is inside. -1 in front matter.
  ///
  /// The panel's highlight and the hint saved with the position both read
  /// this, which is why the walk itself sits in `library_book.dart` where a
  /// test can reach it without a widget tree.
  int get _currentChapter => chapterIndexAt(_chapters, _session.index);

  /// What tapping the *centre* of the surface does right now, for a screen
  /// reader.
  ///
  /// The centre is the app's primary control — play, pause, and advance under
  /// elicited pacing — and the whole surface was a bare `GestureDetector`
  /// with no role and no label, so TalkBack found nothing on it at all. The
  /// edges have their own labels below; this one no longer describes them.
  String get _surfaceLabel => switch (_session.state) {
    PlaybackState.playing => 'Pause reading',
    PlaybackState.awaitingAdvance => 'Next word',
    PlaybackState.finished => 'End of book',
    _ => 'Start reading',
  };

  /// The edges, which name a number the reader chose in Settings and cannot
  /// see from here.
  String get _backLabel => 'Back $_stepWords word${_stepWords == 1 ? '' : 's'}';

  String get _forwardLabel =>
      'Forward $_stepWords word${_stepWords == 1 ? '' : 's'}';

  /// The whole reading surface as one control, for continuous scroll.
  ///
  /// The three tap zones do not exist in this mode. They are a fixed-anchor
  /// arrangement — a reader who can drag to any word does not need an edge
  /// that steps by a configured number of them — so they are absent rather
  /// than present and inert, which is the choice ADR 0020 already made about
  /// controls that do nothing.
  ///
  /// One semantics node, not three. A screen-reader user finding three
  /// buttons where a sighted user finds one surface would be reading a
  /// different app. `onIncrease` and `onDecrease` carry the stepping the edge
  /// zones used to: `SemanticsAction.increase` is the idiom for a control
  /// moving along a continuum, which this surface literally is, and TalkBack
  /// and NVDA offer it as a swipe on the focused node. Deleting the edges
  /// with no replacement would regress the exact axis ADR 0020 was written to
  /// fix.
  ///
  /// No `liveRegion`. ADR 0020 declined one at four words a second; sixty
  /// frames a second is not the case that changes the answer.
  Widget _scrollRegion(PlaybackState state) {
    // Hoisted out of the builder below so its elements are reused. Only the
    // Semantics wrapper is rebuilt when the stream emits.
    final surface = Listener(
      onPointerDown: (_) => _grabSurface(),
      onPointerCancel: (_) => _releaseSurface(),
      onPointerSignal: _onSurfaceSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // The role and the label are on the Semantics above.
        excludeFromSemantics: true,
        // Tap and horizontal drag share one arena, so past `kTouchSlop` the
        // drag accepts and on an early lift the tap wins. That is the rule
        // this surface wants, and it is stock Flutter — no custom
        // recognizer. `onHorizontalDrag*` rather than `onPan*` because a pan
        // recognizer would claim the vertical axis this surface does not use.
        onTap: _scrollTap,
        // The content follows the finger: dragging right moves the reader
        // backward. Pinned by a test rather than left to whoever next reads
        // this minus sign.
        onHorizontalDragUpdate: (d) => _scrubSurface(-d.delta.dx),
        // `details.primaryVelocity` is deliberately ignored. No fling: the
        // reader stops where they let go, and momentum would carry them past
        // the word they were aiming at.
        onHorizontalDragEnd: (_) => _releaseSurface(),
        child: const SizedBox.expand(),
      ),
    );

    return ValueListenableBuilder<PlaybackUpdate?>(
      valueListenable: _current,
      builder: (_, update, _) {
        // The same rule the centre zone follows, literally: the word is
        // offered only while the stream is stopped. Two labels for one
        // control is how they come apart.
        final word = state == PlaybackState.playing
            ? ''
            : (update?.token?.text ?? '');

        return Semantics(
          key: readerScrollSurfaceKey,
          button: true,
          label: _surfaceLabel,
          value: word,
          // Both or neither: `SemanticsNode` asserts that a node offering
          // `increase` has a value exactly when it has an increased value.
          // Blank while playing is the right half of that anyway — a node
          // announcing no word should not announce the word a step away
          // either. The actions stay live throughout.
          increasedValue: word.isEmpty
              ? ''
              : _wordAt(_session.index + _stepWords),
          decreasedValue: word.isEmpty
              ? ''
              : _wordAt(_session.index - _stepWords),
          onTap: _onSurfaceTap,
          onIncrease: () => _whenReading(_stepForward),
          onDecrease: () => _whenReading(_stepBack),
          child: surface,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _session.state;
    final showControls = state != PlaybackState.playing;

    // Off the session rather than off the resolved presentation, so one
    // object answers "is this a marquee" for the gesture, the clock and the
    // surface alike.
    final scrolling = _session.scrolling;

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
    final presentation = _presentation;

    final ink = colorOf(readerInkArgbFor(presentation));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeOrDismiss();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): _onSurfaceTap,
          // The same two actions the edge zones carry, so a reader on a
          // keyboard and a reader with a thumb are doing one thing rather
          // than two that drift.
          //
          // Both changed with the zones. Right was a bare `advance`, always
          // one token and never stopping; Left stepped by the profile's
          // `rewindWords` and kept playing. Neither matched the other, and
          // the settings page described both as "one word".
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _whenReading(_stepForward),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _whenReading(_stepBack),
          // The four sentence and paragraph jumps, modifier-keyed so the
          // bare arrows keep stepping by `_stepWords`. Through `_jumpTo`
          // like the buttons, so a key at the end of the book is a no-op
          // rather than something a disabled button would not do.
          const SingleActivator(
            LogicalKeyboardKey.arrowRight,
            control: true,
          ): () =>
              _jumpTo(_nextSentence)?.call(),
          const SingleActivator(
            LogicalKeyboardKey.arrowLeft,
            control: true,
          ): () =>
              _jumpTo(_previousSentence)?.call(),
          const SingleActivator(
            LogicalKeyboardKey.arrowRight,
            shift: true,
          ): () =>
              _jumpTo(_nextParagraph)?.call(),
          const SingleActivator(
            LogicalKeyboardKey.arrowLeft,
            shift: true,
          ): () =>
              _jumpTo(_previousParagraph)?.call(),
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
              body: Stack(
                children: [
                  Positioned.fill(
                    // Paint only. The roles and the labels are on the
                    // regions above, which are what a reader actually
                    // presses; a word announced as its own node beside three
                    // buttons would make the surface four things.
                    //
                    // Which surface a profile draws is decided in one place,
                    // and the settings preview calls the same one. See
                    // [ReadingSurface] for why a `switch (mode)` here as well
                    // would reopen the hole that had the contrast readout
                    // measuring a pair the app never painted.
                    child: ExcludeSemantics(
                      child: ReadingSurface(
                        updates: _current,
                        presentation: presentation,
                        layout: _clock.layout,
                      ),
                    ),
                  ),

                  // Three regions rather than one, at a fixed anchor. The
                  // edges step and stop; the centre keeps play, pause and
                  // the elicited advance. Continuous scroll replaces all
                  // three with one draggable surface — see [_scrollRegion],
                  // and ADR 0025 for why the zones are a fixed-anchor
                  // arrangement rather than a reader-facing concept.
                  //
                  // Flex 1/2/1 rather than arithmetic over a measured width:
                  // it puts the 25/50/25 split in the layout, which is also
                  // where a screen reader reads the geometry of each button
                  // from. A generous centre because that tap is the primary
                  // control and a mis-hit costs the reader their place in a
                  // sentence.
                  //
                  // Before the controls in this list, so the close, profile,
                  // play, chapter and jump buttons sit above the zones and
                  // keep their own taps. The detector this replaced wrapped
                  // all of them.
                  Positioned.fill(
                    child: scrolling
                        ? _scrollRegion(state)
                        : Row(
                            children: [
                              Expanded(
                                child: _TapZone(
                                  key: readerTapBackKey,
                                  label: _backLabel,
                                  onTap: () => _whenReading(_stepBack),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                // The word is announced by the control that stops
                                // on it, so this one node follows the stream while
                                // the two edges do not. The `Row` and its
                                // `Expanded`s are built once either way.
                                child: ValueListenableBuilder<PlaybackUpdate?>(
                                  valueListenable: _current,
                                  builder: (_, update, _) => _TapZone(
                                    key: readerTapCentreKey,
                                    label: _surfaceLabel,
                                    // Offered only while the stream is stopped. A
                                    // reader using RSVP is reading with their
                                    // eyes, and speech four times a second would
                                    // fight that rather than serve it — anyone who
                                    // needs speech instead of sight is better
                                    // served by the whole book read aloud than by
                                    // one word at a time. Paused, stepped or
                                    // rewound, the word on screen is one fact
                                    // worth having on focus, and each of those is
                                    // something the reader just did.
                                    value: state == PlaybackState.playing
                                        ? ''
                                        : (update?.token?.text ?? ''),
                                    onTap: _onSurfaceTap,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: _TapZone(
                                  key: readerTapForwardKey,
                                  label: _forwardLabel,
                                  onTap: () => _whenReading(_stepForward),
                                ),
                              ),
                            ],
                          ),
                  ),
                  if (state == PlaybackState.finished)
                    Center(
                      child: Text('End of book', style: TextStyle(color: ink)),
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
                          // A list rather than a book: the book glyph is
                          // what the Library tab uses, and the same
                          // picture meaning "your books" in one place and
                          // "this book's chapters" in another is a picture
                          // meaning two things. Both are named in
                          // `AppIcons`, which is where that distinction is
                          // visible side by side.
                          child: IconButton(
                            onPressed: _openChapters,
                            iconSize: _secondaryIconSize,
                            color: ink,
                            icon: const Icon(AppIcons.chapters),
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
                            // Null where there is no next one, so the
                            // control is absent rather than present and
                            // inert at the end of the book.
                            onSentence: _jumpTo(_nextSentence),
                            onParagraph: _jumpTo(_nextParagraph),
                            onBackSentence: _jumpTo(_previousSentence),
                            onBackParagraph: _jumpTo(_previousParagraph),
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
    );
  }
}

/// The book's own table of contents, as a panel.
///
/// Read-only and flat. Depth is shown as indentation rather than as
/// collapsible sections: a reader looking for Act III Scene II wants to see
/// it, not to expand Act III first.
class _ChapterPanel extends StatefulWidget {
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
  State<_ChapterPanel> createState() => _ChapterPanelState();
}

class _ChapterPanelState extends State<_ChapterPanel> {
  final _controller = ScrollController();
  final _currentKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    // In initState because `DrawerController` does not build its child while
    // the drawer is dismissed, so this state is created afresh every time the
    // panel opens — which is exactly when the reveal is wanted, and only
    // then. A reader who scrolls away afterwards is not dragged back.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Scrolls the chapter being read into view.
  ///
  /// Two steps, because a lazy list has no element for a tile that has never
  /// been on screen and `ensureVisible` cannot scroll to one that does not
  /// exist. The jump is an estimate — the scrollable's own extent, divided by
  /// index — which is exact for uniform tiles and close enough for wrapped
  /// ones to bring the target into the build window. `ensureVisible` then
  /// places it properly. The estimate is never the final word, so a title
  /// that wraps costs a few pixels of scroll and nothing else.
  void _revealCurrent() {
    if (!mounted || widget.currentIndex < 0) return;
    if (!_controller.hasClients || widget.chapters.length < 2) return;

    final position = _controller.position;
    final fraction = widget.currentIndex / (widget.chapters.length - 1);

    _controller.jumpTo(
      (position.maxScrollExtent * fraction).clamp(0, position.maxScrollExtent),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _currentKey.currentContext;
      if (!mounted || target == null) return;

      // Centred rather than pinned to the top edge: the chapters either side
      // are how a reader confirms it is the right one.
      unawaited(Scrollable.ensureVisible(target, alignment: 0.5));
    });
  }

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
                  Text(widget.bookTitle, style: theme.textTheme.titleMedium),
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
                controller: _controller,
                itemCount: widget.chapters.length,
                itemBuilder: (context, i) {
                  final chapter = widget.chapters[i];

                  return ListTile(
                    key: i == widget.currentIndex ? _currentKey : null,
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
                    selected: i == widget.currentIndex,
                    onTap: () => widget.onSelected(chapter),
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

/// One of the three regions the reading surface is divided into.
///
/// The gesture and the semantics are on one widget rather than the gesture
/// here and the role somewhere below it, so the announced button and the
/// pressable area cannot come apart. [Semantics] takes its geometry from its
/// child, and the child fills its share of the [Row], which is what makes the
/// 25/50/25 split legible to a screen reader without any of it being written
/// down twice.
///
/// Opaque rather than deferring to what is painted underneath: the reading
/// surface is mostly empty background, and a zone that only answered where a
/// word happened to be would be a control that moved with the text.
class _TapZone extends StatelessWidget {
  final String label;

  /// The word on screen, announced on focus while the stream is stopped.
  /// Only the centre carries one; see the call site.
  final String? value;

  final VoidCallback onTap;

  const _TapZone({
    super.key,
    required this.label,
    required this.onTap,
    this.value,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    value: value ?? '',
    onTap: onTap,
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // The role and the label are on the Semantics above. Left on, the
      // detector reports a second tappable node inside the first.
      excludeFromSemantics: true,
      child: const SizedBox.expand(),
    ),
  );
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

/// A disabled glyph, in the same ink as every enabled one.
///
/// Material's own disabled opacity, rather than a number picked here, so a
/// control that cannot be pressed on the reading surface looks like one that
/// cannot be pressed anywhere else in the app.
Color _dimmed(Color ink) => ink.withValues(alpha: 0.38);

/// Progress, a row of four sentence and paragraph jumps, then exit, play and
/// profile.
///
/// **Order.** Outward from play in the nav row: back-paragraph, back-sentence,
/// forward-sentence, forward-paragraph. Distance from the centre matches
/// distance travelled, and the two directions mirror each other. See ADR
/// 0021, which moved play into its own row beneath the jumps — un-rejecting
/// ADR 0020's "two rows" alternative now that the row holds four jumps
/// instead of two.
///
/// Takes the resolved presentation rather than a colour. The row needs three
/// colours that all derive from the background, and passing one in while
/// deriving the others here would put half the answer in the caller.
///
/// The panels this screen opens take the app's neutral ramp; this row does
/// not. It sits on whatever the reader picked in the background field, which
/// the ramp knows nothing about.
class _Controls extends StatelessWidget {
  final PlaybackState state;
  final double progress;
  final ResolvedPresentation presentation;
  final VoidCallback onClose;
  final VoidCallback onToggle;
  final VoidCallback onProfile;

  /// Null at the end of the book, where there is no next sentence or
  /// paragraph to reach. A disabled control says that; a working one that
  /// moves nowhere does not.
  final VoidCallback? onSentence;
  final VoidCallback? onParagraph;

  /// Null at the very start of the book, for the same reason. See ADR 0021.
  final VoidCallback? onBackSentence;
  final VoidCallback? onBackParagraph;

  const _Controls({
    required this.state,
    required this.progress,
    required this.presentation,
    required this.onClose,
    required this.onToggle,
    required this.onProfile,
    required this.onSentence,
    required this.onParagraph,
    required this.onBackSentence,
    required this.onBackParagraph,
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
                  key: readerBackParagraphButtonKey,
                  onPressed: onBackParagraph,
                  iconSize: _secondaryIconSize,
                  color: ink,
                  // `color` is the enabled colour only, and this row sets it
                  // explicitly rather than taking a scheme role, so the
                  // disabled one has to be set explicitly too or the glyph
                  // falls back to the theme's `onSurface` over a background
                  // the theme has never seen. The same ink, dimmed: nothing
                  // else on this screen could carry "unavailable", and ADR
                  // 0015's one ink is not broken by an opacity.
                  disabledColor: _dimmed(ink),
                  icon: const Icon(AppIcons.backParagraph),
                  tooltip: 'Back a paragraph',
                ),
                IconButton(
                  key: readerBackSentenceButtonKey,
                  onPressed: onBackSentence,
                  iconSize: _secondaryIconSize,
                  color: ink,
                  disabledColor: _dimmed(ink),
                  icon: const Icon(AppIcons.backSentence),
                  tooltip: 'Back a sentence',
                ),
                IconButton(
                  key: readerSentenceButtonKey,
                  onPressed: onSentence,
                  iconSize: _secondaryIconSize,
                  color: ink,
                  disabledColor: _dimmed(ink),
                  icon: const Icon(AppIcons.skipSentence),
                  tooltip: 'Forward a sentence',
                ),
                IconButton(
                  key: readerParagraphButtonKey,
                  onPressed: onParagraph,
                  iconSize: _secondaryIconSize,
                  color: ink,
                  disabledColor: _dimmed(ink),
                  icon: const Icon(AppIcons.skipParagraph),
                  tooltip: 'Forward a paragraph',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: onClose,
                  iconSize: _secondaryIconSize,
                  color: ink,
                  icon: const Icon(AppIcons.closeBook),
                  tooltip: 'Back to library',
                ),
                IconButton(
                  key: readerPlayButtonKey,
                  onPressed: onToggle,
                  iconSize: _primaryIconSize,
                  color: ink,
                  icon: Icon(stopping ? AppIcons.pause : AppIcons.play),
                  tooltip: toggleLabel,
                ),
                IconButton(
                  key: readerProfileButtonKey,
                  onPressed: onProfile,
                  iconSize: _secondaryIconSize,
                  color: ink,
                  icon: const Icon(AppIcons.readingProfile),
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
