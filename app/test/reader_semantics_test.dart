import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'test_database.dart';

Future<String> _stamp() async => '0000000000001-00000-test';

TokenizedText _text() => TokenizedText.from(const [
  (id: 'one', text: 'Alpha beta gamma delta epsilon zeta eta theta.'),
  (id: 'two', text: 'Iota kappa lambda mu nu xi omicron pi.'),
], parserVersion: 1);

void main() {
  late AppDatabase database;
  late TokenizedText text;

  setUp(() {
    database = AppDatabase(testExecutor());
    text = _text();
  });

  tearDown(() => database.close());

  Widget reader() => MaterialApp(
    home: ReaderScreen(
      book: LibraryBook(id: 'b', title: 'A Book', text: text),
      repository: LibraryRepository(database),
      issueStamp: _stamp,
      onSave: (_) async {},
    ),
  );

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Opens the reader with a sliding profile already active.
  Future<void> openScrolling(WidgetTester tester) async {
    final repository = LibraryRepository(database);
    final profile = ReadingProfile(
      id: 'scroll-test',
      name: 'Sliding',
      presentation: const PresentationConfig(
        mode: PresentationMode.continuousScroll,
      ),
    );
    await repository.saveProfile(profile, hlc: await _stamp());
    await repository.setActiveProfile(profile.id, hlc: await _stamp());

    await tester.pumpWidget(reader());
    await tester.pumpAndSettle();
  }

  group('the reading surface', () {
    // The gap this file exists for. The surface is the app's primary
    // control and was a bare GestureDetector: no role, no label, nothing
    // for a screen reader to find or activate.
    //
    // Read off the centre zone rather than off `RsvpView` since ADR 0020
    // split the surface into three. `RsvpView` is paint now, under an
    // `ExcludeSemantics`, and the word it draws is announced by the zone
    // that presses it rather than as a node of its own.
    testWidgets('is a button a screen reader can find and press', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byKey(readerTapCentreKey)),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          label: 'Start reading',
          value: 'Alpha',
        ),
      );

      handle.dispose();
      await disposeTree(tester);
    });

    // The edges are the reader's only way back on a touch screen, so each
    // has to be findable in its own right — and each names a number set on
    // a screen the reader cannot see from here.
    testWidgets('the edges are buttons that say how far they move', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byKey(readerTapBackKey)),
        isSemantics(isButton: true, hasTapAction: true, label: 'Back 1 word'),
      );
      expect(
        tester.getSemantics(find.byKey(readerTapForwardKey)),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          label: 'Forward 1 word',
        ),
      );

      handle.dispose();
      await disposeTree(tester);
    });

    // The word belongs to the control that stops on it, not to the two
    // beside it. Three nodes each announcing it would say it three times.
    testWidgets('only the centre carries the word', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      expect(tester.getSemantics(find.byKey(readerTapBackKey)).value, '');
      expect(tester.getSemantics(find.byKey(readerTapForwardKey)).value, '');
      expect(
        tester.getSemantics(find.byKey(readerTapCentreKey)).value,
        'Alpha',
      );

      handle.dispose();
      await disposeTree(tester);
    });

    // The deliberate part. A word announced on every advance would arrive
    // four times a second and fight the visual stream it is describing.
    testWidgets('says nothing word by word while playing', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pump(const Duration(seconds: 1));

      expect(
        tester.getSemantics(find.byKey(readerTapCentreKey)),
        isSemantics(label: 'Pause reading', value: ''),
      );

      handle.dispose();
      await disposeTree(tester);
    });

    // Paused is different: the word on screen is one fact, and the reader
    // asked for it.
    testWidgets('offers the word once the stream stops', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(readerTapCentreKey));
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.byKey(readerTapCentreKey));
      expect(node.label, 'Start reading');
      expect(node.value, isNotEmpty);

      handle.dispose();
      await disposeTree(tester);
    });
  });

  group('the progress bar', () {
    testWidgets('reports where the reader is', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(LinearProgressIndicator)),
        isSemantics(label: 'Progress through the book'),
      );

      handle.dispose();
      await disposeTree(tester);
    });
  });

  // ADR 0021. `IconButton` carries its tooltip in the semantics node's
  // `tooltip` property, not `label` — unlike the hand-built `_TapZone`
  // semantics above, which set `label` directly. This pins the four new
  // buttons' tooltips alongside the two ADR 0020 already ships.
  group('the sentence and paragraph jumps', () {
    testWidgets('each carries its own tooltip', (tester) async {
      final handle = tester.ensureSemantics();

      // Mid-book, so all four jumps are enabled: a disabled `IconButton`
      // drops its tooltip from the semantics tree along with `onPressed`.
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            book: LibraryBook(
              id: 'b',
              title: 'A Book',
              text: text,
              position: text.locatorAt(4),
            ),
            repository: LibraryRepository(database),
            issueStamp: _stamp,
            onSave: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byKey(readerBackParagraphButtonKey)).tooltip,
        'Back a paragraph',
      );
      expect(
        tester.getSemantics(find.byKey(readerBackSentenceButtonKey)).tooltip,
        'Back a sentence',
      );
      expect(
        tester.getSemantics(find.byKey(readerSentenceButtonKey)).tooltip,
        'Forward a sentence',
      );
      expect(
        tester.getSemantics(find.byKey(readerParagraphButtonKey)).tooltip,
        'Forward a paragraph',
      );

      handle.dispose();
      await disposeTree(tester);
    });
  });

  group('the sliding surface', () {
    // One node, not three. A screen-reader user finding three buttons where
    // a sighted user finds one surface would be reading a different app —
    // and ADR 0020 removed the zones as a concept here, not as pixels.
    testWidgets('is one button carrying the word', (tester) async {
      final handle = tester.ensureSemantics();

      await openScrolling(tester);

      expect(
        tester.getSemantics(find.byKey(readerScrollSurfaceKey)),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          label: 'Start reading',
          value: 'Alpha',
        ),
      );

      expect(find.byKey(readerTapBackKey), findsNothing);
      expect(find.byKey(readerTapCentreKey), findsNothing);
      expect(find.byKey(readerTapForwardKey), findsNothing);

      handle.dispose();
      await disposeTree(tester);
    });

    // The edges were a screen-reader user's only way to step, and deleting
    // them with no replacement would regress the axis this file exists for.
    // `increase`/`decrease` is the idiom for a control moving along a
    // continuum, which this surface literally is; TalkBack and NVDA offer it
    // as a swipe on the focused node.
    testWidgets('steps by the configured amount without the edge zones', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await openScrolling(tester);

      expect(
        tester.getSemantics(find.byKey(readerScrollSurfaceKey)),
        isSemantics(
          hasIncreaseAction: true,
          hasDecreaseAction: true,
          increasedValue: 'beta',
          decreasedValue: 'Alpha',
        ),
      );

      tester.semantics.increase(find.semantics.byLabel('Start reading'));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byKey(readerScrollSurfaceKey)).value,
        'beta',
      );

      handle.dispose();
      await disposeTree(tester);
    });

    // Same rule as the centre zone, and more so: sixty frames a second is an
    // order of magnitude past the rate ADR 0020 already declined to announce.
    testWidgets('says nothing while the text is moving', (tester) async {
      final handle = tester.ensureSemantics();

      await openScrolling(tester);

      await tester.tap(find.byKey(readerScrollSurfaceKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final node = tester.getSemantics(find.byKey(readerScrollSurfaceKey));
      expect(node.label, 'Pause reading');
      expect(node.value, '');
      // Both or neither, which `SemanticsNode` asserts on for a node
      // offering `increase`.
      expect(node.increasedValue, '');
      expect(node.decreasedValue, '');

      await tester.tap(find.byKey(readerScrollSurfaceKey));
      await tester.pumpAndSettle();

      handle.dispose();
      await disposeTree(tester);
    });
  });
}
