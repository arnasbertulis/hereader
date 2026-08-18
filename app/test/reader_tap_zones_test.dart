import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/reader_screen.dart';
import 'package:app/reading/reading_display.dart';
import 'package:app/reading/rsvp_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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

  Widget reader({int startIndex = 0}) => MaterialApp(
    home: ReaderScreen(
      book: LibraryBook(
        id: 'b',
        title: 'A Book',
        text: _text(),
        // `LibraryBook.resumeIndex` is what seeds the session, and opening
        // partway in is the only way to have somewhere to step back to.
        position: startIndex == 0 ? null : _text().locatorAt(startIndex),
      ),
      repository: repository,
      issueStamp: _stamp,
      onSave: (_) async {},
    ),
  );

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

    testWidgets('the centre still starts and stops the stream', (
      tester,
    ) async {
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
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

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
  });
}
