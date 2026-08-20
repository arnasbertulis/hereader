import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/reader_screen.dart';
import 'package:app/reading/rsvp_view.dart';
import 'package:app/reading/scrolling_text_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// **`pumpAndSettle` never settles while a scroll session is playing.**
///
/// The marquee is driven by a `Ticker`, so a playing surface schedules a
/// frame forever by design — the same trap the settings preview's
/// starts-paused rule already guards, now reachable from the reader. Every
/// test below pumps a `Duration` instead. Settling is safe once the session
/// is stopped, which is what every gesture here ends in.

Future<String> _stamp() async => '0000000000001-00000-test';

/// Three blocks. Every word is distinct, so an index names itself.
///
///   0 Alpha  1 beta     2 gamma.   | block one
///   3 Delta  4 epsilon  5 zeta.    | block two
///   6 Eta    7 theta    8 iota.    | block three
TokenizedText _text() => TokenizedText.from(const [
  (id: 'one', text: 'Alpha beta gamma.'),
  (id: 'two', text: 'Delta epsilon zeta.'),
  (id: 'three', text: 'Eta theta iota.'),
], parserVersion: 1);

ReadingProfile _scrollingProfile() => ReadingProfile(
  id: 'scroll-test',
  name: 'Sliding',
  rewindWords: 2,
  pacing: const PacingConfig(baseWpm: 300),
  presentation: const PresentationConfig(
    mode: PresentationMode.continuousScroll,
  ),
);

void main() {
  late AppDatabase database;
  late LibraryRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepository(database);
  });

  tearDown(() => database.close());

  final saves = <ReadingResult>[];

  Widget reader({int startIndex = 0, List<Chapter> chapters = const []}) {
    final book = _text();
    return MaterialApp(
      home: ReaderScreen(
        book: LibraryBook(
          id: 'b',
          title: 'A Book',
          text: book,
          chapters: chapters,
          position: startIndex == 0 ? null : book.locatorAt(startIndex),
        ),
        repository: repository,
        issueStamp: _stamp,
        onSave: (result) async => saves.add(result),
      ),
    );
  }

  /// Opens the reader with a scrolling profile already active.
  ///
  /// Written before `pumpWidget` because the screen reads the active profile
  /// once, asynchronously, and adopts whatever comes back.
  Future<void> open(
    WidgetTester tester, {
    int startIndex = 0,
    List<Chapter> chapters = const [],
  }) async {
    final profile = _scrollingProfile();
    await repository.saveProfile(profile, hlc: await _stamp());
    await repository.setActiveProfile(profile.id, hlc: await _stamp());

    await tester.pumpWidget(reader(startIndex: startIndex, chapters: chapters));
    await tester.pumpAndSettle();
  }

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// What the surface is drawing, read off the painter rather than off
  /// pixels. The painter is handed the same update the session emitted, so
  /// this is the session's own answer to "which token is current".
  PlaybackUpdate? update(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(ScrollingTextView),
        matching: find.byType(CustomPaint),
      ),
    );
    return (paint.painter! as MarqueePainter).updates.value;
  }

  int index(WidgetTester tester) => update(tester)!.index;

  group('the surface a scrolling profile draws', () {
    testWidgets('is the marquee, and the three tap zones are gone', (
      tester,
    ) async {
      await open(tester);

      expect(find.byType(ScrollingTextView), findsOneWidget);
      expect(find.byType(RsvpView), findsNothing);

      expect(find.byKey(readerScrollSurfaceKey), findsOneWidget);
      expect(find.byKey(readerTapBackKey), findsNothing);
      expect(find.byKey(readerTapCentreKey), findsNothing);
      expect(find.byKey(readerTapForwardKey), findsNothing);

      await disposeTree(tester);
    });

    testWidgets('a fixed-anchor profile still draws the zones', (tester) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      expect(find.byType(RsvpView), findsOneWidget);
      expect(find.byType(ScrollingTextView), findsNothing);
      expect(find.byKey(readerTapBackKey), findsOneWidget);
      expect(find.byKey(readerScrollSurfaceKey), findsNothing);

      await disposeTree(tester);
    });
  });

  group('tapping', () {
    testWidgets('a tap starts the text moving, and a second stops it', (
      tester,
    ) async {
      await open(tester);
      expect(update(tester)!.state, isNot(PlaybackState.playing));

      await tester.tap(find.byKey(readerScrollSurfaceKey));
      await tester.pump();
      expect(update(tester)!.state, PlaybackState.playing);

      // Two frames of real motion, then stop. Never pumpAndSettle here.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      await tester.tap(find.byKey(readerScrollSurfaceKey));
      await tester.pump();
      expect(update(tester)!.state, PlaybackState.paused);

      await disposeTree(tester);
    });

    testWidgets('the text stops the moment the finger lands', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(readerScrollSurfaceKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(update(tester)!.state, PlaybackState.playing);

      // Down only. `onTapDown` would be deferred by up to kPressTimeout;
      // the surface listens for the raw pointer instead.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(readerScrollSurfaceKey)),
      );
      await tester.pump();
      expect(update(tester)!.state, PlaybackState.paused);

      await gesture.up();
      await tester.pumpAndSettle();

      await disposeTree(tester);
    });
  });

  group('dragging', () {
    testWidgets('dragging left moves the reader forward', (tester) async {
      await open(tester);
      expect(index(tester), 0);

      await tester.drag(
        find.byKey(readerScrollSurfaceKey),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();

      expect(index(tester), greaterThan(0));

      await disposeTree(tester);
    });

    testWidgets('dragging right moves the reader back', (tester) async {
      await open(tester, startIndex: 6);
      final before = index(tester);

      await tester.drag(
        find.byKey(readerScrollSurfaceKey),
        const Offset(400, 0),
      );
      await tester.pumpAndSettle();

      expect(index(tester), lessThan(before));

      await disposeTree(tester);
    });

    testWidgets('a drag leaves the stream stopped where it was released', (
      tester,
    ) async {
      await open(tester);

      await tester.drag(
        find.byKey(readerScrollSurfaceKey),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();

      final landed = index(tester);
      expect(update(tester)!.state, PlaybackState.paused);

      // Nothing moves on its own after the finger lifts. No fling.
      await tester.pump(const Duration(seconds: 1));
      expect(index(tester), landed);

      await disposeTree(tester);
    });

    testWidgets('resuming after a drag does not step back by rewindWords', (
      tester,
    ) async {
      // The scroll twin of the tap-zone rule: a place the reader chose is not
      // undone by the resume rewind. See ADR 0022.
      await open(tester, startIndex: 6);

      await tester.drag(
        find.byKey(readerScrollSurfaceKey),
        const Offset(-100, 0),
      );
      await tester.pumpAndSettle();
      final landed = index(tester);

      await tester.tap(find.byKey(readerScrollSurfaceKey));
      await tester.pump();

      expect(index(tester), landed);
      expect(update(tester)!.state, PlaybackState.playing);

      await tester.tap(find.byKey(readerScrollSurfaceKey));
      await tester.pumpAndSettle();

      await disposeTree(tester);
    });

    testWidgets('a drag from the left edge scrubs and does not open a drawer', (
      tester,
    ) async {
      // `drawerEnableOpenDragGesture: false` is this feature's precondition:
      // a DrawerController would otherwise install its own horizontal drag
      // recognizer over the body and take every scrub starting near the edge.
      // Turned off for an unrelated reason; pinned here so a revert fails.
      await open(
        tester,
        chapters: const [Chapter(title: 'Two', depth: 0, tokenIndex: 3)],
      );

      final y = tester.getCenter(find.byKey(readerScrollSurfaceKey)).dy;
      await tester.dragFrom(Offset(8, y), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(index(tester), greaterThan(0));
      expect(find.byType(Drawer), findsNothing);

      await disposeTree(tester);
    });
  });

  group('what a scroll writes down', () {
    testWidgets('a save mid-word lands on the token under the marker', (
      tester,
    ) async {
      // The locator format is token-granular (ADR 0002), so the sub-token
      // offset is discarded on the way to disk and a resume places the
      // anchor at the token's leading edge. At most one word, and the ADR
      // says so rather than leaving it to be rediscovered as a bug.
      await open(tester);
      saves.clear();

      await tester.tap(find.byKey(readerScrollSurfaceKey));
      await tester.pump();
      // Long enough to cross a few words and land partway into one, so the
      // discarded offset is a real quantity rather than zero.
      for (var i = 0; i < 44; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final current = update(tester)!;
      expect(current.tokenOffset, greaterThan(0));
      await tester.tap(find.byKey(readerScrollSurfaceKey));
      await tester.pumpAndSettle();

      expect(saves, isNotEmpty);
      expect(saves.last.tokenIndex, current.index);
      expect(
        saves.last.locator.charOffset,
        _text().tokens[current.index].charOffset,
      );

      await disposeTree(tester);
    });
  });

  group('the controls still work', () {
    testWidgets('the four jumps land and leave the stream stopped', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.byKey(readerParagraphButtonKey));
      await tester.pumpAndSettle();

      expect(index(tester), 3);
      expect(update(tester)!.state, PlaybackState.paused);
      // A jump lands on a leading edge, so the marker sits at the start of
      // the word rather than partway into it.
      expect(update(tester)!.tokenOffset, 0);

      await tester.tap(find.byKey(readerSentenceButtonKey));
      await tester.pumpAndSettle();
      expect(index(tester), 6);

      await tester.tap(find.byKey(readerBackSentenceButtonKey));
      await tester.pumpAndSettle();
      expect(index(tester), lessThan(6));

      await disposeTree(tester);
    });

    testWidgets('the play button still starts and stops the marquee', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pump();
      expect(update(tester)!.state, PlaybackState.playing);

      await tester.pump(const Duration(milliseconds: 16));

      // The controls hide while playing, so the surface is what stops it —
      // unchanged from the fixed anchor.
      expect(find.byKey(readerPlayButtonKey), findsNothing);

      await tester.tap(find.byKey(readerScrollSurfaceKey));
      await tester.pumpAndSettle();
      expect(update(tester)!.state, PlaybackState.paused);
      expect(find.byKey(readerPlayButtonKey), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('a chapter choice lands and stays stopped', (tester) async {
      await open(
        tester,
        chapters: const [
          Chapter(title: 'One', depth: 0, tokenIndex: 0),
          Chapter(title: 'Three', depth: 0, tokenIndex: 6),
        ],
      );

      await tester.tap(find.byTooltip('Chapters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Three'));
      await tester.pumpAndSettle();

      expect(index(tester), 6);
      expect(update(tester)!.state, PlaybackState.paused);

      await disposeTree(tester);
    });
  });
}
