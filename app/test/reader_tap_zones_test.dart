import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/reader_screen.dart';
import 'package:app/reading/reading_display.dart';
import 'package:app/reading/rsvp_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

Future<String> _stamp() async => '0000000000001-00000-test';

/// Three blocks, so a paragraph jump has somewhere to land and the last one
/// has nowhere. Every word is distinct, so the word on screen names the index
/// without a count.
///
/// Tokens:
///   0 Alpha  1 beta     2 gamma.   | block one
///   3 Delta  4 epsilon  5 zeta.    | block two
///   6 Eta    7 theta    8 iota.    | block three
TokenizedText _text() => TokenizedText.from(const [
  (id: 'one', text: 'Alpha beta gamma.'),
  (id: 'two', text: 'Delta epsilon zeta.'),
  (id: 'three', text: 'Eta theta iota.'),
], parserVersion: 1);

/// Two blocks of several sentences each, so a sentence jump has to work
/// mid-block rather than always landing on a block's own first token — the
/// shape [_text] never exercises, since every block there is one sentence.
///
/// Tokens:
///   0 Alpha  1 beta.   2 Gamma  3 delta.   4 Epsilon  5 zeta.  | block one
///   6 Eta    7 theta.  8 Iota   9 kappa.                        | block two
TokenizedText _multiSentenceText() => TokenizedText.from(const [
  (id: 'one', text: 'Alpha beta. Gamma delta. Epsilon zeta.'),
  (id: 'two', text: 'Eta theta. Iota kappa.'),
], parserVersion: 1);

/// The word the reading surface is showing, which is the only thing on screen
/// that names where the reader is.
String _word(WidgetTester tester) =>
    tester.widget<RsvpView>(find.byType(RsvpView)).update?.token?.text ?? '';

void main() {
  late AppDatabase database;
  late LibraryRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepository(database);
  });

  tearDown(() => database.close());

  Widget reader({int startIndex = 0, TokenizedText? text}) {
    final book = text ?? _text();
    return MaterialApp(
      home: ReaderScreen(
        book: LibraryBook(
          id: 'b',
          title: 'A Book',
          text: book,
          // `LibraryBook.resumeIndex` is what seeds the session, and opening
          // partway in is the only way to have somewhere to step back to.
          position: startIndex == 0 ? null : book.locatorAt(startIndex),
        ),
        repository: repository,
        issueStamp: _stamp,
        onSave: (_) async {},
      ),
    );
  }

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Writes the preference the reader screen reads at open. Has to run before
  /// `pumpWidget`, since the screen reads it once and does not watch it.
  Future<void> setStep(int words) => ReadingDisplayController(
    repository: repository,
    issueStamp: _stamp,
  ).setStepWords(words);

  group('the edge zones', () {
    testWidgets('the right edge moves forward and stops', (tester) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      expect(_word(tester), 'Alpha');

      await tester.tap(find.byKey(readerTapForwardKey));
      await tester.pumpAndSettle();

      expect(_word(tester), 'beta');

      // Stopped, not running on. The controls are hidden while playing, so
      // their presence is the assertion that the stream is not moving.
      expect(find.byKey(readerPlayButtonKey), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('the left edge moves back and stops', (tester) async {
      await tester.pumpWidget(reader(startIndex: 4));
      await tester.pumpAndSettle();

      expect(_word(tester), 'epsilon');

      await tester.tap(find.byKey(readerTapBackKey));
      await tester.pumpAndSettle();

      expect(_word(tester), 'Delta');
      expect(find.byKey(readerPlayButtonKey), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('a tap while playing stops the stream', (tester) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pump(const Duration(milliseconds: 400));

      // Playing, so the controls are gone.
      expect(find.byKey(readerPlayButtonKey), findsNothing);

      await tester.tap(find.byKey(readerTapBackKey));
      await tester.pumpAndSettle();

      expect(find.byKey(readerPlayButtonKey), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('both edges move by the configured step', (tester) async {
      await setStep(3);

      await tester.pumpWidget(reader(startIndex: 4));
      // The step is read from the database after the first frame, the same
      // way the profile is, so this has to settle before either edge means
      // anything.
      await tester.pumpAndSettle();

      expect(_word(tester), 'epsilon');

      await tester.tap(find.byKey(readerTapBackKey));
      await tester.pumpAndSettle();
      expect(_word(tester), 'beta');

      await tester.tap(find.byKey(readerTapForwardKey));
      await tester.pumpAndSettle();
      expect(_word(tester), 'epsilon');

      await disposeTree(tester);
    });

    testWidgets('the ends clamp rather than throwing', (tester) async {
      await setStep(10);

      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerTapBackKey));
      await tester.pumpAndSettle();
      expect(_word(tester), 'Alpha');

      await tester.tap(find.byKey(readerTapForwardKey));
      await tester.pumpAndSettle();
      expect(_word(tester), 'iota.');

      await disposeTree(tester);
    });

    testWidgets('the centre still starts and stops the stream', (tester) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerTapCentreKey));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(readerPlayButtonKey), findsNothing);

      await tester.tap(find.byKey(readerTapCentreKey));
      await tester.pumpAndSettle();
      expect(find.byKey(readerPlayButtonKey), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('the controls sit above the zones and keep their taps', (
      tester,
    ) async {
      // The zone row fills the surface, so a control drawn under it would be
      // invisible to a tap while still being on screen. Nothing else in the
      // suite would notice: the play button would simply do nothing, and
      // every other test reaches playback through a different route.
      await tester.pumpWidget(reader(startIndex: 4));
      await tester.pumpAndSettle();

      // The nav row's back buttons sit over the lower part of the left tap
      // zone (ADR 0021), which is the geometry this test exists to guard —
      // extended here rather than left to the forward-jump case alone.
      await tester.tap(find.byKey(readerBackSentenceButtonKey));
      await tester.pumpAndSettle();
      expect(_word(tester), 'Delta');

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(readerPlayButtonKey), findsNothing);

      await disposeTree(tester);
    });
  });

  group('the forward jumps', () {
    testWidgets('a sentence lands on the word after the full stop', (
      tester,
    ) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerSentenceButtonKey));
      await tester.pumpAndSettle();

      expect(_word(tester), 'Delta');

      await disposeTree(tester);
    });

    testWidgets('a paragraph lands on the first word of the next block', (
      tester,
    ) async {
      await tester.pumpWidget(reader(startIndex: 1));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerParagraphButtonKey));
      await tester.pumpAndSettle();

      expect(_word(tester), 'Delta');

      await disposeTree(tester);
    });

    testWidgets('both are disabled in the last paragraph', (tester) async {
      await tester.pumpWidget(reader(startIndex: 7));
      await tester.pumpAndSettle();

      expect(_word(tester), 'theta');

      // Disabled rather than absent: the row keeps its shape, and a control
      // that moved nowhere would be worse than one that says it cannot.
      expect(
        tester
            .widget<IconButton>(find.byKey(readerSentenceButtonKey))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(readerParagraphButtonKey))
            .onPressed,
        isNull,
      );

      await disposeTree(tester);
    });

    testWidgets('a jump leaves the stream stopped', (tester) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(readerPlayButtonKey), findsNothing);

      // The controls are hidden while playing, so these buttons are only
      // reachable once the stream has stopped. What is worth pinning is that
      // pressing one does not start it again.
      await tester.tap(find.byKey(readerTapCentreKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerParagraphButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(readerPlayButtonKey), findsOneWidget);

      await disposeTree(tester);
    });
  });

  group('the backward jumps', () {
    testWidgets('mid-sentence restarts the sentence', (tester) async {
      // Token 5 is "zeta.", the last word of the third sentence ("Epsilon
      // zeta.") but not its first — mid-sentence, so this restarts it.
      await tester.pumpWidget(
        reader(startIndex: 5, text: _multiSentenceText()),
      );
      await tester.pumpAndSettle();

      expect(_word(tester), 'zeta.');

      await tester.tap(find.byKey(readerBackSentenceButtonKey));
      await tester.pumpAndSettle();

      expect(_word(tester), 'Epsilon');

      await disposeTree(tester);
    });

    testWidgets('already on a sentence start moves to the one before', (
      tester,
    ) async {
      // Token 4 is "Epsilon", already the third sentence's own first word,
      // so the first press moves past it rather than restarting it.
      await tester.pumpWidget(
        reader(startIndex: 4, text: _multiSentenceText()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerBackSentenceButtonKey));
      await tester.pumpAndSettle();
      expect(_word(tester), 'Gamma');

      await tester.tap(find.byKey(readerBackSentenceButtonKey));
      await tester.pumpAndSettle();
      expect(_word(tester), 'Alpha');

      await disposeTree(tester);
    });

    testWidgets('mid-paragraph restarts the paragraph', (tester) async {
      await tester.pumpWidget(
        reader(startIndex: 3, text: _multiSentenceText()),
      );
      await tester.pumpAndSettle();

      expect(_word(tester), 'delta.');

      await tester.tap(find.byKey(readerBackParagraphButtonKey));
      await tester.pumpAndSettle();

      expect(_word(tester), 'Alpha');

      await disposeTree(tester);
    });

    testWidgets('already on a block start moves to the block before', (
      tester,
    ) async {
      await tester.pumpWidget(
        reader(startIndex: 6, text: _multiSentenceText()),
      );
      await tester.pumpAndSettle();

      expect(_word(tester), 'Eta');

      await tester.tap(find.byKey(readerBackParagraphButtonKey));
      await tester.pumpAndSettle();

      expect(_word(tester), 'Alpha');

      await disposeTree(tester);
    });

    testWidgets('both back buttons are disabled at the very start', (
      tester,
    ) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      expect(_word(tester), 'Alpha');

      expect(
        tester
            .widget<IconButton>(find.byKey(readerBackSentenceButtonKey))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(readerBackParagraphButtonKey))
            .onPressed,
        isNull,
      );

      await disposeTree(tester);
    });

    testWidgets('a backward jump leaves the stream stopped', (tester) async {
      await tester.pumpWidget(reader(startIndex: 4));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(readerPlayButtonKey), findsNothing);

      await tester.tap(find.byKey(readerTapCentreKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerBackParagraphButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(readerPlayButtonKey), findsOneWidget);

      await disposeTree(tester);
    });
  });

  group('the four jumps by keyboard', () {
    Future<void> holdAndPress(
      WidgetTester tester,
      LogicalKeyboardKey modifier,
      LogicalKeyboardKey key,
    ) async {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+Right moves forward a sentence', (tester) async {
      await tester.pumpWidget(reader(text: _multiSentenceText()));
      await tester.pumpAndSettle();

      await holdAndPress(
        tester,
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.arrowRight,
      );

      expect(_word(tester), 'Gamma');

      await disposeTree(tester);
    });

    testWidgets('Ctrl+Left moves back a sentence', (tester) async {
      await tester.pumpWidget(
        reader(startIndex: 5, text: _multiSentenceText()),
      );
      await tester.pumpAndSettle();

      await holdAndPress(
        tester,
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.arrowLeft,
      );

      expect(_word(tester), 'Epsilon');

      await disposeTree(tester);
    });

    testWidgets('Shift+Right moves forward a paragraph', (tester) async {
      await tester.pumpWidget(reader(startIndex: 1));
      await tester.pumpAndSettle();

      await holdAndPress(
        tester,
        LogicalKeyboardKey.shift,
        LogicalKeyboardKey.arrowRight,
      );

      expect(_word(tester), 'Delta');

      await disposeTree(tester);
    });

    testWidgets('Shift+Left moves back a paragraph', (tester) async {
      // Token 3 is "Delta", already the second block's own first word, so
      // the press moves past it to the first block's start.
      await tester.pumpWidget(reader(startIndex: 3));
      await tester.pumpAndSettle();

      await holdAndPress(
        tester,
        LogicalKeyboardKey.shift,
        LogicalKeyboardKey.arrowLeft,
      );

      expect(_word(tester), 'Alpha');

      await disposeTree(tester);
    });

    testWidgets('a key at the end of the book is a no-op', (tester) async {
      await tester.pumpWidget(reader(startIndex: 7));
      await tester.pumpAndSettle();

      expect(_word(tester), 'theta');

      await holdAndPress(
        tester,
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.arrowRight,
      );

      expect(_word(tester), 'theta');

      await disposeTree(tester);
    });

    testWidgets('the bare arrows still step by the configured amount', (
      tester,
    ) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(_word(tester), 'beta');

      await disposeTree(tester);
    });
  });

  group('resuming after a step', () {
    testWidgets('does not step back again by rewindWords', (tester) async {
      // The fault this exists for. `rewindWords` defaults to 2, and under a
      // tap zone a step and a resume land one after the other on every
      // press, so an unsuppressed rewind would undo the step and then some.
      await tester.pumpWidget(reader(startIndex: 4));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerTapForwardKey));
      await tester.pumpAndSettle();
      expect(_word(tester), 'zeta.');

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pump();

      expect(_word(tester), 'zeta.');

      await disposeTree(tester);
    });

    testWidgets('does not step back again after a back-sentence jump', (
      tester,
    ) async {
      await tester.pumpWidget(reader(startIndex: 7));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerBackSentenceButtonKey));
      await tester.pumpAndSettle();
      expect(_word(tester), 'Eta');

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pump();

      expect(_word(tester), 'Eta');

      await disposeTree(tester);
    });

    testWidgets('does not step back again after a back-paragraph jump', (
      tester,
    ) async {
      await tester.pumpWidget(reader(startIndex: 4));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerBackParagraphButtonKey));
      await tester.pumpAndSettle();
      expect(_word(tester), 'Delta');

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pump();

      expect(_word(tester), 'Delta');

      await disposeTree(tester);
    });
  });

  // `_text()` never puts more than one sentence in a block, so nothing above
  // exercises a jump from *inside* a multi-sentence block on the reader
  // screen — every landing there is also a block boundary. This group closes
  // that gap.
  group('the forward jumps against multi-sentence prose', () {
    testWidgets('from the first sentence lands on the second sentence', (
      tester,
    ) async {
      await tester.pumpWidget(reader(text: _multiSentenceText()));
      await tester.pumpAndSettle();

      expect(_word(tester), 'Alpha');

      await tester.tap(find.byKey(readerSentenceButtonKey));
      await tester.pumpAndSettle();

      expect(_word(tester), 'Gamma');

      await disposeTree(tester);
    });

    testWidgets('from the last word of a sentence lands on the next sentence', (
      tester,
    ) async {
      await tester.pumpWidget(
        reader(startIndex: 1, text: _multiSentenceText()),
      );
      await tester.pumpAndSettle();

      expect(_word(tester), 'beta.');

      await tester.tap(find.byKey(readerSentenceButtonKey));
      await tester.pumpAndSettle();

      expect(_word(tester), 'Gamma');

      await disposeTree(tester);
    });

    testWidgets('from the middle of the second sentence lands correctly', (
      tester,
    ) async {
      await tester.pumpWidget(
        reader(startIndex: 2, text: _multiSentenceText()),
      );
      await tester.pumpAndSettle();

      expect(_word(tester), 'Gamma');

      await tester.tap(find.byKey(readerSentenceButtonKey));
      await tester.pumpAndSettle();

      expect(_word(tester), 'Epsilon');

      await disposeTree(tester);
    });

    testWidgets('a paragraph jump from mid-block lands on the next block', (
      tester,
    ) async {
      await tester.pumpWidget(
        reader(startIndex: 3, text: _multiSentenceText()),
      );
      await tester.pumpAndSettle();

      expect(_word(tester), 'delta.');

      await tester.tap(find.byKey(readerParagraphButtonKey));
      await tester.pumpAndSettle();

      expect(_word(tester), 'Eta');

      await disposeTree(tester);
    });

    testWidgets('a jump under elicited pacing lands correctly too', (
      tester,
    ) async {
      // `awaitingAdvance` is the one state `stopAt` re-schedules instead of
      // pausing (ADR 0020 section 2). Controls stay visible throughout it,
      // since `showControls` is false only while `playing`.
      await repository.setActiveProfile(
        Presets.centralFieldLoss.id,
        hlc: await _stamp(),
      );

      await tester.pumpWidget(reader(text: _multiSentenceText()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pumpAndSettle();

      expect(_word(tester), 'Alpha');

      await tester.tap(find.byKey(readerSentenceButtonKey));
      await tester.pumpAndSettle();

      expect(_word(tester), 'Gamma');

      await disposeTree(tester);
    });

    testWidgets('a jump survives a pause taken after it, before resuming', (
      tester,
    ) async {
      // `stopAt` suppresses exactly one resume rewind, and
      // `PlaybackSession.pause` clears that suppression when it runs.
      // Opening the profile sheet calls `pause()`, but the session is
      // already `paused` from the jump, and `pause()` guards on the state
      // already being `playing` or `awaitingAdvance` — so the sheet's call
      // never reaches the line that clears the suppression. `_resumeHere`
      // survives untouched, and resuming after the sheet closes lands back
      // exactly where the jump left it. ADR 0020 section 2's "any pause()
      // clears it" is true of `pause()` running, not of calling it — the
      // distinction this test pins.
      await tester.pumpWidget(reader(text: _multiSentenceText()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerSentenceButtonKey));
      await tester.pumpAndSettle();
      expect(_word(tester), 'Gamma');

      await tester.tap(find.byKey(readerProfileButtonKey));
      await tester.pumpAndSettle();
      // Dismiss the sheet by tapping its scrim.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pump();

      expect(_word(tester), 'Gamma');

      await disposeTree(tester);
    });
  });
}
