import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/profile_edit_screen.dart';
import 'package:app/reading/profile_presentation.dart';
import 'package:app/reading/reader_screen.dart';
import 'package:app/reading/rsvp_view.dart';
import 'package:app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'test_database.dart';

Future<String> _stamp() async => '0000000000001-00000-test';

PlaybackUpdate _showing(String word) => PlaybackUpdate(
  state: PlaybackState.paused,
  index: 0,
  token: Token(text: word, charOffset: 0),
);

/// Global x of the point [anchorX] of the way along the glyph run the
/// paragraph painted, wherever its box and textAlign put that run.
double _paintedFixationX(RenderParagraph paragraph, double anchorX) {
  final start = paragraph
      .getOffsetForCaret(const TextPosition(offset: 0), Rect.zero)
      .dx;
  final width = paragraph.getMaxIntrinsicWidth(double.infinity);
  return paragraph.localToGlobal(Offset(start + anchorX * width, 0)).dx;
}

/// The `[start, end)` code-unit offsets RsvpView marked as the ORP highlight,
/// read off the painted RichText's own span tree rather than recomputed —
/// the highlighted child is the only one carrying a style override.
({int start, int end}) _highlightOffsets(RenderParagraph paragraph) {
  // Text.rich wraps the TextSpan it is given in one more TextSpan carrying
  // the effective style, so RsvpView's own three-child span sits one level
  // down from what RenderParagraph.text exposes.
  final root = paragraph.text as TextSpan;
  final wrapped = root.children!.single as TextSpan;
  var offset = 0;
  for (final span in wrapped.children!.cast<TextSpan>()) {
    final text = span.text!;
    if (span.style != null) {
      return (start: offset, end: offset + text.length);
    }
    offset += text.length;
  }
  throw StateError('no highlighted span found in $root');
}

ReadingProfile _profile({
  PresentationConfig presentation = const PresentationConfig(),
  PacingConfig pacing = const PacingConfig(),
}) => ReadingProfile(
  id: 'p.test',
  name: 'Test',
  pacing: pacing,
  presentation: presentation,
);

TokenizedText _text() => TokenizedText.from(const [
  (id: 'one', text: 'Alpha beta gamma delta epsilon zeta eta theta.'),
], parserVersion: 1);

/// What the reading surface actually painted behind the word.
Color _paintedSurface(WidgetTester tester) => tester
    .widgetList<ColoredBox>(
      find.descendant(
        of: find.byType(RsvpView),
        matching: find.byType(ColoredBox),
      ),
    )
    .first
    .color;

/// Disposes the widget tree inside the test body, so drift's zero-duration
/// cancellation timer is pumped rather than reported as a leak.
Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  group('the reading surface', () {
    // The regression this file exists for. RsvpView carried its own ink and
    // surface constants, four values that had drifted from the four in
    // profile_presentation.dart, so the WCAG readout in settings measured a
    // pair of colours nothing ever painted.
    for (final polarity in Polarity.values) {
      testWidgets('paints the ${polarity.name} colours the readout judges', (
        tester,
      ) async {
        final presentation = resolvePresentation(
          PresentationConfig(polarity: polarity),
          Brightness.light,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: RsvpView(
              update: _showing('reading'),
              presentation: presentation,
            ),
          ),
        );

        expect(_paintedSurface(tester), colorOf(surfaceArgbFor(presentation)));

        final word = tester.widget<Text>(find.text('reading'));
        expect(word.style?.color, colorOf(inkArgbFor(polarity)));
      });
    }

    testWidgets('a tint overrides the polarity surface', (tester) async {
      final presentation = resolvePresentation(
        const PresentationConfig(tintArgb: 0xFF102030),
        Brightness.light,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RsvpView(
            update: _showing('reading'),
            presentation: presentation,
          ),
        ),
      );

      expect(_paintedSurface(tester), const Color(0xFF102030));
    });

    // ADR 0016, at the widget rather than at the function. The same config
    // paints two different pages depending on which brightness resolved it,
    // and neither of them is a value written into the profile.
    testWidgets('a profile stating no polarity paints the app it is in', (
      tester,
    ) async {
      for (final entry in {
        Brightness.light: lightSurfaceArgb,
        Brightness.dark: darkSurfaceArgb,
      }.entries) {
        await tester.pumpWidget(
          MaterialApp(
            home: RsvpView(
              update: _showing('reading'),
              presentation: resolvePresentation(
                const PresentationConfig(),
                entry.key,
              ),
            ),
          ),
        );

        expect(
          _paintedSurface(tester),
          colorOf(entry.value),
          reason: 'a following profile ignored the ${entry.key} app',
        );
      }
    });

    // #365. Before this, a token wider than the viewport wrapped across
    // several lines and pushed the fixation point up, which is the one
    // thing this surface exists not to do (ADR 0035 §4).
    testWidgets('shrinks a word wider than the viewport to one line', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;

      const longWord = 'pneumonoultramicroscopicsilicovolcanoconiosis';
      const presentation = PresentationConfig(fontSizePt: 44);
      final resolved = resolvePresentation(presentation, Brightness.light);

      await tester.pumpWidget(
        MaterialApp(
          home: RsvpView(update: _showing(longWord), presentation: resolved),
        ),
      );

      final word = tester.widget<Text>(find.text(longWord));
      expect(word.maxLines, 1);
      expect(word.softWrap, false);
      expect(word.style?.fontSize, lessThan(presentation.fontSizePt));
      expect(
        word.style!.fontSize!,
        greaterThanOrEqualTo(PresentationConfig.minFontSizePt),
      );

      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(RsvpView),
          matching: find.byType(RichText),
        ),
      );
      expect(paragraph.didExceedMaxLines, false);
    });

    testWidgets('a word that fits keeps the profile font size', (tester) async {
      addTearDown(tester.view.reset);
      // Wide enough that the word fits without shrinking, and at or below
      // scaledFontSizePt's 400px reference width so grow-to-fill leaves the
      // profile's own font size untouched too — isolating this test to the
      // shrink-to-fit path leaving a fitting word alone.
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;

      const presentation = PresentationConfig(fontSizePt: 44);
      final resolved = resolvePresentation(presentation, Brightness.light);

      await tester.pumpWidget(
        MaterialApp(
          home: RsvpView(update: _showing('reading'), presentation: resolved),
        ),
      );

      final word = tester.widget<Text>(find.text('reading'));
      expect(word.style?.fontSize, presentation.fontSizePt);
    });

    testWidgets(
      'floors an extreme word at minFontSizePt instead of shrinking further',
      (tester) async {
        addTearDown(tester.view.reset);
        tester.view.physicalSize = const Size(150, 400);
        tester.view.devicePixelRatio = 1.0;

        // Long enough that even the floor size overflows 150 logical px, so
        // this exercises the clip path rather than only the shrink path.
        const extremeWord =
            'pneumonoultramicroscopicsilicovolcanoconiosisantidisestablishmentarianism';
        const presentation = PresentationConfig(fontSizePt: 44);
        final resolved = resolvePresentation(presentation, Brightness.light);

        await tester.pumpWidget(
          MaterialApp(
            home: RsvpView(
              update: _showing(extremeWord),
              presentation: resolved,
            ),
          ),
        );

        final word = tester.widget<Text>(find.text(extremeWord));
        expect(word.style?.fontSize, PresentationConfig.minFontSizePt);
        expect(word.maxLines, 1);
      },
    );

    // #468. A word still wider than availableTextWidth at minFontSizePt used
    // to paint straight past the reading surface: the Text/Text.rich sat in
    // an unconstrained Padding, so overflow: TextOverflow.clip never had a
    // box to clip against. Every word, fitting or overflowing, is now placed
    // in one fixed-width clip box aligned at anchorX, so the fixation point
    // -- the point anchorX of the way along the word -- stays put even when
    // the excess is clipped from both ends (ADR 0035 §4, #468 amendment).
    for (final anchorX in [0.0, 0.3, 0.5, 1.0]) {
      testWidgets('holds the fixation point and clips a floor-overflowing word, '
          'anchorX $anchorX', (tester) async {
        addTearDown(tester.view.reset);
        tester.view.physicalSize = const Size(150, 400);
        tester.view.devicePixelRatio = 1.0;

        const extremeWord =
            'pneumonoultramicroscopicsilicovolcanoconiosisantidisestablishmentarianism';
        final presentation = PresentationConfig(
          fontSizePt: 44,
          anchorX: anchorX,
        );
        final resolved = resolvePresentation(presentation, Brightness.light);

        await tester.pumpWidget(
          MaterialApp(
            home: RsvpView(
              update: _showing(extremeWord),
              presentation: resolved,
            ),
          ),
        );

        const availableTextWidth = 150.0 - 32.0;

        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byType(RsvpView),
            matching: find.byType(RichText),
          ),
        );
        expect(
          paragraph.getMaxIntrinsicWidth(double.infinity),
          greaterThan(availableTextWidth),
        );

        expect(
          _paintedFixationX(paragraph, anchorX),
          closeTo(16 + anchorX * availableTextWidth, 1.0),
        );

        final clipRect = tester.getRect(
          find
              .ancestor(
                of: find.byType(RichText),
                matching: find.byType(ClipRect),
              )
              .first,
        );
        expect(clipRect.left, closeTo(16, 1.0));
        expect(clipRect.right, closeTo(16 + availableTextWidth, 1.0));
      });
    }

    testWidgets(
      'holds the fixation point for a fitting, non-overflowing word too',
      (tester) async {
        addTearDown(tester.view.reset);
        tester.view.physicalSize = const Size(150, 400);
        tester.view.devicePixelRatio = 1.0;

        const anchorX = 0.3;
        final presentation = PresentationConfig(
          fontSizePt: 44,
          anchorX: anchorX,
        );
        final resolved = resolvePresentation(presentation, Brightness.light);

        await tester.pumpWidget(
          MaterialApp(
            home: RsvpView(update: _showing('cat'), presentation: resolved),
          ),
        );

        const availableTextWidth = 150.0 - 32.0;

        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byType(RsvpView),
            matching: find.byType(RichText),
          ),
        );

        expect(
          _paintedFixationX(paragraph, anchorX),
          closeTo(16 + anchorX * availableTextWidth, 1.0),
        );
      },
    );

    // #475. The ORP highlight always marked letter 0-3 from the start of the
    // word, counted in UTF-16 code units. Once a word is clipped at the
    // floor (#468), that letter can be off screen or can split a combining
    // mark's code units apart, so the highlight moves to the whole grapheme
    // cluster under the fixation point instead (ADR 0035 §4, #475
    // amendment).
    group('#475. ORP highlight follows the fixation point when floored', () {
      const extremeWord =
          'pneumonoultramicroscopicsilicovolcanoconiosisantidisestablishmentarianism';

      for (final anchorX in [0.0, 0.3, 0.5, 1.0]) {
        testWidgets('highlights the letter under the fixation point for a '
            'floor-overflowing word, anchorX $anchorX', (tester) async {
          addTearDown(tester.view.reset);
          tester.view.physicalSize = const Size(150, 400);
          tester.view.devicePixelRatio = 1.0;

          final presentation = PresentationConfig(
            fontSizePt: 44,
            anchorX: anchorX,
            orpHighlight: true,
          );
          final resolved = resolvePresentation(presentation, Brightness.light);

          await tester.pumpWidget(
            MaterialApp(
              home: Material(
                child: RsvpView(
                  update: _showing(extremeWord),
                  presentation: resolved,
                ),
              ),
            ),
          );

          const availableTextWidth = 150.0 - 32.0;

          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.byType(RsvpView),
              matching: find.byType(RichText),
            ),
          );
          expect(
            paragraph.getMaxIntrinsicWidth(double.infinity),
            greaterThan(availableTextWidth),
          );

          final offsets = _highlightOffsets(paragraph);
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: offsets.start, extentOffset: offsets.end),
          );
          expect(boxes, isNotEmpty);
          final globalLeft = paragraph
              .localToGlobal(Offset(boxes.first.left, 0))
              .dx;
          final globalRight = paragraph
              .localToGlobal(Offset(boxes.last.right, 0))
              .dx;

          final fixationX = 16 + anchorX * availableTextWidth;
          expect(fixationX, greaterThanOrEqualTo(globalLeft - 1.0));
          expect(fixationX, lessThanOrEqualTo(globalRight + 1.0));

          final clipRect = tester.getRect(
            find
                .ancestor(
                  of: find.byType(RichText),
                  matching: find.byType(ClipRect),
                )
                .first,
          );
          expect(globalLeft, greaterThanOrEqualTo(clipRect.left - 1.0));
          expect(globalRight, lessThanOrEqualTo(clipRect.right + 1.0));
        });
      }

      testWidgets('keeps the ORP rule\'s letter for a fitting word', (
        tester,
      ) async {
        addTearDown(tester.view.reset);
        tester.view.physicalSize = const Size(150, 400);
        tester.view.devicePixelRatio = 1.0;

        final presentation = PresentationConfig(
          fontSizePt: 44,
          anchorX: 0.3,
          orpHighlight: true,
        );
        final resolved = resolvePresentation(presentation, Brightness.light);

        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: RsvpView(update: _showing('cat'), presentation: resolved),
            ),
          ),
        );

        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byType(RsvpView),
            matching: find.byType(RichText),
          ),
        );

        // 'cat' has 3 clusters; the ORP rule (unchanged from before #475)
        // marks index 1, the letter 'a'.
        final offsets = _highlightOffsets(paragraph);
        expect(offsets.start, 1);
        expect(offsets.end, 2);
      });

      testWidgets(
        'highlights a whole grapheme cluster, never half of one, for a '
        'fitting word made of one combining-mark letter',
        (tester) async {
          addTearDown(tester.view.reset);
          tester.view.physicalSize = const Size(150, 400);
          tester.view.devicePixelRatio = 1.0;

          // 'e' + combining acute accent (U+0301): one grapheme cluster,
          // "é", spanning two UTF-16 code units.
          const word = 'é';
          final presentation = PresentationConfig(
            fontSizePt: 44,
            orpHighlight: true,
          );
          final resolved = resolvePresentation(presentation, Brightness.light);

          await tester.pumpWidget(
            MaterialApp(
              home: Material(
                child: RsvpView(update: _showing(word), presentation: resolved),
              ),
            ),
          );

          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.byType(RsvpView),
              matching: find.byType(RichText),
            ),
          );

          final offsets = _highlightOffsets(paragraph);
          expect(offsets.start, 0);
          expect(offsets.end, word.length);
        },
      );

      testWidgets(
        'highlights a whole grapheme cluster, never half of one, for a '
        'floor-overflowing word made of combining-mark letters',
        (tester) async {
          addTearDown(tester.view.reset);
          tester.view.physicalSize = const Size(150, 400);
          tester.view.devicePixelRatio = 1.0;

          // 40 repeats of 'z' + combining acute accent: a floor-overflowing
          // word where every grapheme cluster is two UTF-16 code units, so a
          // highlight that split a cluster would show up as an odd-length or
          // misaligned range.
          final word = 'ź' * 40;
          const anchorX = 0.6;
          final presentation = PresentationConfig(
            fontSizePt: 44,
            anchorX: anchorX,
            orpHighlight: true,
          );
          final resolved = resolvePresentation(presentation, Brightness.light);

          await tester.pumpWidget(
            MaterialApp(
              home: Material(
                child: RsvpView(update: _showing(word), presentation: resolved),
              ),
            ),
          );

          const availableTextWidth = 150.0 - 32.0;
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.byType(RsvpView),
              matching: find.byType(RichText),
            ),
          );
          expect(
            paragraph.getMaxIntrinsicWidth(double.infinity),
            greaterThan(availableTextWidth),
          );

          final offsets = _highlightOffsets(paragraph);
          expect(offsets.end - offsets.start, 2);
          expect(word.substring(offsets.start, offsets.end), 'ź');
        },
      );

      testWidgets(
        "keeps the ORP rule's letter when the floor overflow is within the "
        'half-pixel tolerance',
        (tester) async {
          addTearDown(tester.view.reset);
          tester.view.devicePixelRatio = 1.0;

          const word = 'antidisestablishmentarianism';
          final presentation = PresentationConfig(
            fontSizePt: 44,
            orpHighlight: true,
          );
          final resolved = resolvePresentation(presentation, Brightness.light);

          // Independent measurement -- Flutter's own TextPainter, not
          // fitFontSizePt -- of the word's width at the floor size, to build
          // a viewport that overflows by less than the 0.5-physical-pixel
          // tolerance FitResult.overflowsAtFloor applies (ADR 0035 §4, #475
          // amendment).
          final floorPainter = TextPainter(
            text: TextSpan(
              text: word,
              style: readingTextStyle(
                resolved,
                fontSizePt: PresentationConfig.minFontSizePt,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();

          final availableTextWidth = floorPainter.width - 0.3;
          tester.view.physicalSize = Size(availableTextWidth + 32.0, 400);

          await tester.pumpWidget(
            MaterialApp(
              home: Material(
                child: RsvpView(update: _showing(word), presentation: resolved),
              ),
            ),
          );

          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.byType(RsvpView),
              matching: find.byType(RichText),
            ),
          );

          final clusters = word.characters.toList();
          var expectedStart = 0;
          for (var i = 0; i < 3; i++) {
            expectedStart += clusters[i].length;
          }

          final offsets = _highlightOffsets(paragraph);
          expect(offsets.start, expectedStart);
          expect(offsets.end, expectedStart + clusters[3].length);
        },
      );
    });

    // #467. fitFontSizePt's TextPainter measured at TextScaler.noScaling
    // while Text/Text.rich painted at the ambient scaler, so an ordinary
    // word — not an outlier like the ones above — could be fit to a width
    // narrower than what it was actually painted at and run past the
    // surface. ADR 0035 §4's amendment: the two must agree.
    testWidgets(
      'shrinks an ordinary word to fit under a non-1.0 ambient text scale',
      (tester) async {
        addTearDown(tester.view.reset);
        tester.view.physicalSize = const Size(320, 600);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        const word = 'extraordinary';
        const presentation = PresentationConfig(fontSizePt: 44);
        final resolved = resolvePresentation(presentation, Brightness.light);

        await tester.pumpWidget(
          MaterialApp(
            home: RsvpView(update: _showing(word), presentation: resolved),
          ),
        );

        final rendered = tester.widget<Text>(find.text(word));
        expect(rendered.style?.fontSize, lessThan(presentation.fontSizePt));

        // The width actually painted — at the ambient scaler Text inherits —
        // must fit inside the surface's available width (viewport minus the
        // 16px horizontal padding on each side), not merely the width
        // fitFontSizePt measured at some other scaler. fitFontSizePt scales
        // the size linearly and glyph shaping doesn't quite follow, so "fits"
        // holds to half a physical pixel; the clip box absorbs the remainder.
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byType(RsvpView),
            matching: find.byType(RichText),
          ),
        );
        expect(paragraph.didExceedMaxLines, false);
        expect(
          paragraph.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(320 - 32 + 0.5 / tester.view.devicePixelRatio),
        );
      },
    );
  });

  group('the reader screen', () {
    late AppDatabase database;

    setUp(() => database = AppDatabase(testExecutor()));
    tearDown(() => database.close());

    // The wiring ADR 0016 is for. Nothing in this test names a polarity: the
    // book opens on `Presets.standard`, which states none, so the page has to
    // come from the theme the app is in. Opening a book from a dark library
    // into a white surface is the discomfort this closes.
    //
    // Both brightnesses in one test, because the claim is that the two differ
    // rather than that either one is a particular colour.
    Widget reader(Brightness app) => MaterialApp(
      theme: appTheme(brightness: app),
      home: ReaderScreen(
        book: LibraryBook(id: 'b', title: 'A Book', text: _text()),
        repository: LibraryRepository(database),
        issueStamp: _stamp,
        onSave: (_) async {},
      ),
    );

    testWidgets('opens a following profile on the app theme', (tester) async {
      await tester.pumpWidget(reader(Brightness.dark));
      await tester.pumpAndSettle();

      expect(_paintedSurface(tester), colorOf(darkSurfaceArgb));

      await tester.pumpWidget(reader(Brightness.light));
      await tester.pumpAndSettle();

      expect(_paintedSurface(tester), colorOf(lightSurfaceArgb));

      await _disposeTree(tester);
    });
  });

  group('the settings preview', () {
    late AppDatabase database;

    setUp(() => database = AppDatabase(testExecutor()));
    tearDown(() => database.close());

    Widget editor(
      ReadingProfile profile, {
      Brightness app = Brightness.light,
    }) => MaterialApp(
      theme: appTheme(brightness: app),
      home: ProfileEditScreen(
        profile: profile,
        repository: LibraryRepository(database),
        issueStamp: _stamp,
      ),
    );

    testWidgets(
      'draws through the reading surface rather than its own sample',
      (tester) async {
        await tester.pumpWidget(editor(_profile()));
        await tester.pumpAndSettle();

        expect(find.byType(RsvpView), findsOneWidget);

        await _disposeTree(tester);
      },
    );

    testWidgets('shows the fixation highlight, which it could not before', (
      tester,
    ) async {
      await tester.pumpWidget(
        editor(
          _profile(presentation: const PresentationConfig(orpHighlight: true)),
        ),
      );
      await tester.pumpAndSettle();

      // Text.rich rather than Text is the whole difference: the old preview
      // drew a plain Text and could not mark a letter at all.
      expect(find.text('Reading,', findRichText: true), findsOneWidget);

      await _disposeTree(tester);
    });

    testWidgets('is still until asked to run, then advances', (tester) async {
      await tester.pumpWidget(editor(_profile()));
      await tester.pumpAndSettle();

      // Nothing moves on its own. The suite depends on this as much as the
      // reader does: an animating preview means pumpAndSettle never returns
      // in any test that opens this screen.
      expect(find.text('Reading,'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Reading,'), findsOneWidget);

      await tester.tap(find.byTooltip('Preview reading'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      // Either the next word, or the blank the anchor holds during a
      // punctuation gap. Both mean the session is running.
      expect(find.text('Reading,'), findsNothing);

      await tester.tap(find.byTooltip('Stop the preview'));
      await tester.pump();

      await _disposeTree(tester);
    });

    testWidgets('previews a following profile on the app theme', (
      tester,
    ) async {
      // The preview and the contrast readout under it both draw from one
      // resolution. If this screen resolved lower down, the readout would go
      // on reporting the unresolved pair while the reader looked at this.
      await tester.pumpWidget(editor(_profile(), app: Brightness.dark));
      await tester.pumpAndSettle();

      expect(_paintedSurface(tester), colorOf(darkSurfaceArgb));

      await _disposeTree(tester);
    });

    testWidgets('pins the page it was on when following is turned off', (
      tester,
    ) async {
      // A dark app, a profile that follows it, and a reader who reaches for
      // the switch. What they pin is the surface in front of them, not the
      // class default, so nothing on screen moves when they do it.
      //
      // A tall physical size, so the editor's ListView mounts every row's
      // sliver in one pass. ADR 0031 raised every role that used to sit
      // below the 16px base — the switch and the polarity control are far
      // enough down the list that, at a phone-sized viewport, the default
      // Scrollable can flicker out of `find.byType(Scrollable)` mid-drag as
      // the name field's own EditableText scrollable mounts and unmounts
      // around it.
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(editor(_profile(), app: Brightness.dark));
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(profileFollowAppKey);
      final polarityFinder = find.byType(SegmentedButton<Polarity>);
      final scrollable = find.byType(Scrollable).first;

      // Named rather than left to default. `scrollUntilVisible` resolves its
      // own default to the single Scrollable in the tree, and the name field
      // builds an EditableText with a Scrollable of its own, so the default
      // matches two and throws before it scrolls anything. The list is the
      // outer one, so it comes first.
      //
      // Scrolled to on its own, right before each use, rather than once up
      // front: the switch and the polarity control are two separate list
      // items, and stacking every SettingSlider's value under its label
      // (ADR 0033) grew everything above them, so a single scroll that
      // happens to land both on screen at once is not guaranteed.
      // `scrollUntilVisible` stops as soon as the target is built, which can
      // leave it off the visible viewport once a later call scrolls past it
      // for the other target — and it skips straight past that early-exit
      // without re-centring on a call where the target is already built.
      // `ensureVisible` is unconditional, so it re-centres every time.
      Future<void> showSwitch() async {
        await tester.scrollUntilVisible(
          switchFinder,
          100,
          scrollable: scrollable,
        );
        await tester.ensureVisible(switchFinder);
        await tester.pumpAndSettle();
      }

      Future<void> showPolarity() async {
        await tester.scrollUntilVisible(
          polarityFinder,
          100,
          scrollable: scrollable,
        );
        await tester.ensureVisible(polarityFinder);
        await tester.pumpAndSettle();
      }

      await showSwitch();
      expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);

      SegmentedButton<Polarity> polarityControl() =>
          tester.widget<SegmentedButton<Polarity>>(polarityFinder);

      // Following, so the control shows the side the app put it on and takes
      // no input.
      await showPolarity();
      expect(polarityControl().selected, {Polarity.lightOnDark});
      expect(polarityControl().onSelectionChanged, isNull);

      await showSwitch();
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

      await showPolarity();
      expect(polarityControl().selected, {Polarity.lightOnDark});
      expect(polarityControl().onSelectionChanged, isNotNull);

      await _disposeTree(tester);
    });
  });
}
