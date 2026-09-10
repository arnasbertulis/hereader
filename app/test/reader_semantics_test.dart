import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/info_dot.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'test_database.dart';

/// Every control on the transport row, keyed rather than found by label —
/// ADR 0037's own instruction. A chaptered book is required for this list
/// to be exhaustive: Chapters only exists in the tree when the book
/// declares any (see 'the legend lists Chapters only for a chaptered
/// book' below).
const _transportControlKeys = [
  readerTapBackKey,
  readerTapForwardKey,
  readerBackParagraphButtonKey,
  readerBackSentenceButtonKey,
  readerSentenceButtonKey,
  readerParagraphButtonKey,
  readerChaptersButtonKey,
  readerBackToLibraryButtonKey,
  readerPlayButtonKey,
  readerProfileButtonKey,
];

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

  // The decision on #413: every control a screen reader can land on has to
  // say what it is, and say it only once. `label` carries that for the
  // hand-built tap zones (ADR 0020); `tooltip` carries it for every
  // `IconButton` (the comment on the group above explains why that is a
  // separate `SemanticsData` field, not `label`, for those). Either way, a
  // visible `Text` descendant would be ADR 0037 §1 painting the name a
  // second time.
  group('every transport control names itself and nothing paints it', () {
    testWidgets(
      'each control has a non-empty accessible name and no Text descendant',
      (tester) async {
        final handle = tester.ensureSemantics();

        await tester.pumpWidget(
          MaterialApp(
            home: ReaderScreen(
              book: LibraryBook(
                id: 'b',
                title: 'A Book',
                text: text,
                chapters: [
                  Chapter(
                    title: 'Chapter One',
                    depth: 0,
                    tokenIndex: text.startOfBlock('one')!,
                  ),
                  Chapter(
                    title: 'Chapter Two',
                    depth: 0,
                    tokenIndex: text.startOfBlock('two')!,
                  ),
                ],
              ),
              repository: LibraryRepository(database),
              issueStamp: _stamp,
              onSave: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final key in _transportControlKeys) {
          final node = tester.getSemantics(find.byKey(key));
          final accessibleName = node.label.isNotEmpty
              ? node.label
              : node.tooltip;
          expect(
            accessibleName,
            isNotEmpty,
            reason: '$key has no label and no tooltip',
          );
          expect(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(Text),
            ),
            findsNothing,
            reason: '$key paints a Text descendant',
          );
        }

        handle.dispose();
        await disposeTree(tester);
      },
    );
  });

  // ADR 0035 §1: hierarchy on this row is size and position, never fill or
  // colour. Every control passes `color: ink` and nothing on the row sets a
  // `style` with its own `backgroundColor` — this pins both halves of that
  // rule so a future control cannot earn prominence by being filled.
  group('the transport row never fills or tints a control', () {
    testWidgets('every control shares one ink colour and draws no fill', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            book: LibraryBook(
              id: 'b',
              title: 'A Book',
              text: text,
              chapters: [
                Chapter(
                  title: 'Chapter One',
                  depth: 0,
                  tokenIndex: text.startOfBlock('one')!,
                ),
                Chapter(
                  title: 'Chapter Two',
                  depth: 0,
                  tokenIndex: text.startOfBlock('two')!,
                ),
              ],
            ),
            repository: LibraryRepository(database),
            issueStamp: _stamp,
            onSave: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      const iconButtonKeys = [
        readerBackParagraphButtonKey,
        readerBackSentenceButtonKey,
        readerSentenceButtonKey,
        readerParagraphButtonKey,
        readerChaptersButtonKey,
        readerBackToLibraryButtonKey,
        readerPlayButtonKey,
        readerProfileButtonKey,
      ];

      final colours = <Color?>{};
      for (final key in iconButtonKeys) {
        final button = tester.widget<IconButton>(find.byKey(key));
        expect(
          button.style,
          isNull,
          reason: '$key sets a ButtonStyle, which can carry a fill',
        );
        colours.add(button.color);
      }

      expect(
        colours,
        hasLength(1),
        reason:
            'every transport control should resolve the same ink colour, '
            'never one of its own',
      );

      await disposeTree(tester);
    });
  });

  group('the transport legend', () {
    // ADR 0037 §1: no transport control draws a text label any more,
    // including the two axis labels ADR 0035 §3 added.
    testWidgets('no transport control draws a visible text label', (
      tester,
    ) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      expect(find.text('Sentence'), findsNothing);
      expect(find.text('Paragraph'), findsNothing);
      expect(find.text('Back to library'), findsNothing);
      expect(find.text('Read'), findsNothing);
      expect(find.text('Reading profile'), findsNothing);

      await disposeTree(tester);
    });

    // ADR 0037 §2: the (i) is chrome, shown only while paused like
    // everything else on the row.
    testWidgets(
      'the InfoDot is present while paused and absent while playing',
      (tester) async {
        await tester.pumpWidget(reader());
        await tester.pumpAndSettle();

        expect(find.byKey(readerLegendInfoDotKey), findsOneWidget);

        await tester.tap(find.byKey(readerPlayButtonKey));
        await tester.pump();

        expect(find.byKey(readerLegendInfoDotKey), findsNothing);

        await disposeTree(tester);
      },
    );

    testWidgets(
      'opening it names every control currently on the row, and the two '
      'gestures no glyph carries',
      (tester) async {
        await tester.pumpWidget(reader());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(readerLegendInfoDotKey));
        await tester.pumpAndSettle();

        expect(find.byKey(readerLegendEntryBackParagraphKey), findsOneWidget);
        expect(find.byKey(readerLegendEntryBackSentenceKey), findsOneWidget);
        expect(find.byKey(readerLegendEntryForwardSentenceKey), findsOneWidget);
        expect(
          find.byKey(readerLegendEntryForwardParagraphKey),
          findsOneWidget,
        );
        expect(find.byKey(readerLegendEntryBackToLibraryKey), findsOneWidget);
        expect(find.byKey(readerLegendEntryPlayKey), findsOneWidget);
        expect(find.byKey(readerLegendEntryReadingProfileKey), findsOneWidget);
        // The book behind `reader()` declares no chapters.
        expect(find.byKey(readerLegendEntryChaptersKey), findsNothing);
        expect(find.byKey(readerLegendEntryTapAnywhereKey), findsOneWidget);
        expect(find.byKey(readerLegendEntryDragSidewaysKey), findsOneWidget);

        await disposeTree(tester);
      },
    );

    testWidgets('the legend lists Chapters only for a chaptered book', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            book: LibraryBook(
              id: 'b',
              title: 'A Book',
              text: text,
              chapters: [
                Chapter(
                  title: 'Chapter One',
                  depth: 0,
                  tokenIndex: text.startOfBlock('one')!,
                ),
                Chapter(
                  title: 'Chapter Two',
                  depth: 0,
                  tokenIndex: text.startOfBlock('two')!,
                ),
              ],
            ),
            repository: LibraryRepository(database),
            issueStamp: _stamp,
            onSave: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerLegendInfoDotKey));
      await tester.pumpAndSettle();

      expect(find.byKey(readerLegendEntryChaptersKey), findsOneWidget);

      await disposeTree(tester);
    });

    // ADR 0035 §5, carried forward by ADR 0037 §2.
    testWidgets('closing the legend does not start playback', (tester) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerLegendInfoDotKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(infoDotCloseButtonKey));
      await tester.pumpAndSettle();

      expect(
        tester.widget<IconButton>(find.byKey(readerPlayButtonKey)).tooltip,
        'Read',
      );

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
