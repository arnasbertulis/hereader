import 'dart:ui' as ui;

import 'package:app/reading/profile_presentation.dart';
import 'package:app/reading/reading_surface.dart';
import 'package:app/reading/rsvp_view.dart';
import 'package:app/reading/scrolling_text_view.dart';
import 'package:app/reading/token_run_measure.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// The twin of `reading_surface_test.dart` for the sliding surface.
///
/// The rule that file exists for is that the contrast readout in settings
/// measures the pair the app paints. A second surface would reopen that hole
/// one level up — the preview could draw one and the reader the other — so
/// both go through [ReadingSurface] and the pair is asserted here too.

PlaybackUpdate _showing(String word) => PlaybackUpdate(
  state: PlaybackState.paused,
  index: 0,
  token: Token(text: word, charOffset: 0),
);

ResolvedPresentation _resolved({
  PresentationMode mode = PresentationMode.continuousScroll,
  Polarity? polarity,
  int? tintArgb,
  Brightness app = Brightness.light,
  CaretPlacement caretPlacement = CaretPlacement.both,
  CaretStyle caretStyle = CaretStyle.filled,
}) => resolvePresentation(
  PresentationConfig(
    mode: mode,
    polarity: polarity,
    tintArgb: tintArgb,
    caretPlacement: caretPlacement,
    caretStyle: caretStyle,
  ),
  app,
);

Widget _surface(
  ResolvedPresentation presentation, {
  ValueListenable<ScrollLayout?>? layout,
}) => MaterialApp(
  home: ReadingSurface(
    updates: ValueNotifier<PlaybackUpdate?>(_showing('reading')),
    presentation: presentation,
    layout: layout ?? ValueNotifier<ScrollLayout?>(null),
  ),
);

MarqueePainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(ScrollingTextView),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as MarqueePainter;

Color _paintedSurface(WidgetTester tester) => tester
    .widgetList<ColoredBox>(
      find.descendant(
        of: find.byType(ScrollingTextView),
        matching: find.byType(ColoredBox),
      ),
    )
    .first
    .color;

/// Counts what reaches the canvas, so "nothing is drawn" can be asserted as
/// nothing rather than inferred from a picture.
///
/// Both carets and text arrive as draw calls — `drawPath` for the wedges and
/// `drawParagraph` from `TextPainter.paint` for the words — so one counter
/// covers the whole surface.
class _CountingCanvas implements Canvas {
  int draws = 0;

  @override
  void drawPath(Path path, Paint paint) => draws++;

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => draws++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

MarqueePainter _direct(PresentationConfig config) => MarqueePainter(
  updates: ValueNotifier<PlaybackUpdate?>(null),
  layout: ValueNotifier<ScrollLayout?>(null),
  config: config,
  caretColor: const Color(0xFFFFFFFF),
);

double _caretWidth(MarqueePainter painter) =>
    painter.caretPath(0, 0, pointsDown: true).getBounds().width;

double _caretDepth(MarqueePainter painter) =>
    painter.caretPath(0, 0, pointsDown: true).getBounds().height;

void main() {
  group('the dispatcher', () {
    testWidgets('a scrolling profile draws the marquee', (tester) async {
      await tester.pumpWidget(_surface(_resolved()));

      expect(find.byType(ScrollingTextView), findsOneWidget);
      expect(find.byType(RsvpView), findsNothing);
    });

    testWidgets('a fixed-anchor profile draws the word', (tester) async {
      await tester.pumpWidget(
        _surface(_resolved(mode: PresentationMode.fixedSingle)),
      );

      expect(find.byType(RsvpView), findsOneWidget);
      expect(find.byType(ScrollingTextView), findsNothing);
    });

    testWidgets('the unbuilt window mode draws a word rather than nothing', (
      tester,
    ) async {
      // A profile carrying it — from a later build, or over the wire —
      // should read as a book rather than as a blank screen.
      await tester.pumpWidget(
        _surface(_resolved(mode: PresentationMode.shiftingWindow)),
      );

      expect(find.byType(RsvpView), findsOneWidget);
    });
  });

  group('the colours the readout judges', () {
    for (final polarity in Polarity.values) {
      testWidgets('the ${polarity.name} surface is the measured one', (
        tester,
      ) async {
        final presentation = _resolved(polarity: polarity);
        await tester.pumpWidget(_surface(presentation));

        expect(_paintedSurface(tester), colorOf(surfaceArgbFor(presentation)));
        expect(
          readingTextStyle(presentation).color,
          colorOf(inkArgbFor(polarity)),
        );
      });
    }

    testWidgets('a tint overrides the polarity surface here too', (
      tester,
    ) async {
      await tester.pumpWidget(_surface(_resolved(tintArgb: 0xFF102030)));
      expect(_paintedSurface(tester), const Color(0xFF102030));
    });

    testWidgets('a profile stating no polarity follows the app', (
      tester,
    ) async {
      for (final entry in {
        Brightness.light: lightSurfaceArgb,
        Brightness.dark: darkSurfaceArgb,
      }.entries) {
        await tester.pumpWidget(_surface(_resolved(app: entry.key)));
        expect(_paintedSurface(tester), colorOf(entry.value));
      }
    });
  });

  group('the caret', () {
    testWidgets('takes the accent, guarded against the surface behind it', (
      tester,
    ) async {
      // Asserted off the function rather than off pixels, the way
      // `reader_chrome_test.dart` does. `readerCaretFor` measures the accent
      // against `surfaceArgbFor` — what is actually behind the caret —
      // rather than against the progress track, and falls back to the chrome
      // ink where it cannot clear 3:1.
      for (final presentation in [
        _resolved(),
        _resolved(polarity: Polarity.lightOnDark),
        _resolved(tintArgb: 0xFF203040),
      ]) {
        await tester.pumpWidget(_surface(presentation));

        final scheme = Theme.of(
          tester.element(find.byType(ScrollingTextView)),
        ).colorScheme;

        expect(
          _painter(tester).caretColor,
          readerCaretFor(scheme: scheme, presentation: presentation),
        );
      }
    });

    testWidgets('falls back to the ink where the accent cannot be seen', (
      tester,
    ) async {
      // A tint the reader chose that the accent disappears into. The readout
      // warns and does not block, so this case is reachable.
      const scheme = ColorScheme.light(primary: Color(0xFF203040));
      final presentation = _resolved(tintArgb: 0xFF203040);

      expect(
        readerCaretFor(scheme: scheme, presentation: presentation),
        colorOf(readerInkArgbFor(presentation)),
      );
    });

    testWidgets('sits clear of the line rather than over it', (tester) async {
      // The whole point of the change: a marker drawn through the words
      // obscures the one word the reader is trying to read. The tip starts
      // at half a line box away, before the reader's own gap is added.
      expect(MarqueePainter.halfLineEm, greaterThanOrEqualTo(0.6));
      expect(MarqueePainter.caretHeightEm, greaterThan(0));
      expect(const PresentationConfig().caretGapEm, greaterThan(0));
    });

    testWidgets('draws two under `both` and one on the named side', (
      tester,
    ) async {
      await tester.pumpWidget(
        _surface(_resolved(caretPlacement: CaretPlacement.above)),
      );
      expect(_painter(tester).caretTips(100), [lessThan(100)]);

      await tester.pumpWidget(
        _surface(_resolved(caretPlacement: CaretPlacement.below)),
      );
      expect(_painter(tester).caretTips(100), [greaterThan(100)]);

      await tester.pumpWidget(
        _surface(_resolved(caretPlacement: CaretPlacement.both)),
      );
      expect(_painter(tester).caretTips(100), [
        lessThan(100),
        greaterThan(100),
      ]);
    });

    testWidgets('the reader can push it further from the line', (tester) async {
      const near = PresentationConfig(
        mode: PresentationMode.continuousScroll,
        caretPlacement: CaretPlacement.below,
        caretGapEm: 0,
      );
      const far = PresentationConfig(
        mode: PresentationMode.continuousScroll,
        caretPlacement: CaretPlacement.below,
        caretGapEm: 1,
      );

      await tester.pumpWidget(
        _surface(resolvePresentation(near, Brightness.light)),
      );
      final close = _painter(tester).caretTips(100).single;

      await tester.pumpWidget(
        _surface(resolvePresentation(far, Brightness.light)),
      );
      expect(_painter(tester).caretTips(100).single, greaterThan(close));

      // Even at zero the tip clears the line box rather than touching a
      // descender.
      expect(close, greaterThan(100));
    });

    testWidgets('every placement and style paints without throwing', (
      tester,
    ) async {
      for (final placement in CaretPlacement.values) {
        for (final style in CaretStyle.values) {
          await tester.pumpWidget(
            _surface(_resolved(caretPlacement: placement, caretStyle: style)),
          );
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$placement $style');
        }
      }
    });
  });

  group('the caret size and thickness', () {
    const base = PresentationConfig(mode: PresentationMode.continuousScroll);

    testWidgets('scale draws the same wedge larger', (tester) async {
      final small = _direct(base.copyWith(caretScale: 1));
      final large = _direct(base.copyWith(caretScale: 2));

      expect(_caretWidth(large), closeTo(_caretWidth(small) * 2, 0.001));
      expect(_caretDepth(large), closeTo(_caretDepth(small) * 2, 0.001));

      // The proportions are the wedge's, not the slider's.
      expect(
        _caretWidth(large) / _caretDepth(large),
        closeTo(_caretWidth(small) / _caretDepth(small), 0.001),
      );
    });

    testWidgets('scale reaches every style', (tester) async {
      for (final style in CaretStyle.values) {
        final small = _direct(base.copyWith(caretStyle: style, caretScale: 1));
        final large = _direct(base.copyWith(caretStyle: style, caretScale: 2));

        expect(
          _caretWidth(large),
          greaterThan(_caretWidth(small)),
          reason: '$style',
        );
      }
    });

    testWidgets('thickness sets the stroke and size does not', (tester) async {
      final thin = _direct(
        base.copyWith(
          caretStyle: CaretStyle.outline,
          caretThicknessEm: PresentationConfig.minCaretThicknessEm,
        ),
      );
      final thick = _direct(
        base.copyWith(
          caretStyle: CaretStyle.outline,
          caretThicknessEm: PresentationConfig.maxCaretThicknessEm,
        ),
      );

      expect(thick.caretStroke, greaterThan(thin.caretStroke));

      // The two sliders are independent on purpose: a large light marker and
      // a small heavy one are both things a reader may want.
      expect(
        _direct(
          base.copyWith(caretThicknessEm: 0.2, caretScale: 2),
        ).caretStroke,
        _direct(
          base.copyWith(caretThicknessEm: 0.2, caretScale: 0.5),
        ).caretStroke,
      );
    });

    testWidgets('a thin caret at a small type size still draws', (
      tester,
    ) async {
      final tiny = _direct(
        base.copyWith(
          fontSizePt: 8,
          caretThicknessEm: PresentationConfig.minCaretThicknessEm,
        ),
      );

      expect(tiny.caretStroke, MarqueePainter.minCaretStroke);
    });
  });

  group('the end of the book', () {
    /// Three blocks so there is a measured run to draw.
    final text = TokenizedText.from(const [
      (id: 'one', text: 'Alpha beta gamma.'),
      (id: 'two', text: 'Delta epsilon zeta.'),
    ], parserVersion: 1);

    MarqueePainter painterFor(PlaybackState state) {
      const presentation = PresentationConfig(
        mode: PresentationMode.continuousScroll,
      );
      final resolved = resolvePresentation(presentation, Brightness.light);

      return MarqueePainter(
        updates: ValueNotifier<PlaybackUpdate?>(
          PlaybackUpdate(
            state: state,
            index: 2,
            // Null on finishing, which is what the session emits. `RsvpView`
            // draws nothing without a token and so clears for free; this
            // painter is driven by an index and a layout instead.
            token: state == PlaybackState.finished ? null : text.tokens[2],
          ),
        ),
        layout: ValueNotifier<ScrollLayout?>(
          measureRun(
            tokens: text.tokens,
            index: 2,
            style: readingTextStyle(resolved),
            styleKey: scrollStyleKeyFor(presentation),
            chapterStarts: const {},
            isParagraphEnd: text.isParagraphEndAt,
          ),
        ),
        config: presentation,
        caretColor: const Color(0xFFFFFFFF),
      );
    }

    testWidgets('the line and the caret both go', (tester) async {
      // Reported from a screenshot: the notice came up over a line of text
      // that was still sitting there, marked by a caret pointing at a place
      // nobody was reading any more.
      final canvas = _CountingCanvas();
      painterFor(PlaybackState.finished).paint(canvas, const Size(400, 200));

      expect(canvas.draws, 0);
    });

    testWidgets('a stopped session still draws both', (tester) async {
      // The guard against the test above passing for the wrong reason.
      final canvas = _CountingCanvas();
      painterFor(PlaybackState.paused).paint(canvas, const Size(400, 200));

      expect(canvas.draws, greaterThan(0));
    });
  });

  group('the painter', () {
    testWidgets('reads the update the session emitted, not a hit test', (
      tester,
    ) async {
      final updates = ValueNotifier<PlaybackUpdate?>(_showing('reading'));

      await tester.pumpWidget(
        MaterialApp(
          home: ReadingSurface(
            updates: updates,
            presentation: _resolved(),
            layout: ValueNotifier<ScrollLayout?>(null),
          ),
        ),
      );

      expect(_painter(tester).updates.value?.token?.text, 'reading');

      updates.value = PlaybackUpdate(
        state: PlaybackState.paused,
        index: 4,
        token: const Token(text: 'later', charOffset: 20),
        tokenOffset: 12,
      );
      await tester.pump();

      expect(_painter(tester).updates.value?.index, 4);
      expect(_painter(tester).updates.value?.tokenOffset, 12);
    });

    testWidgets('paints a measured run without throwing', (tester) async {
      final text = TokenizedText.from(const [
        (id: 'one', text: 'Alpha beta gamma.'),
        (id: 'two', text: 'Delta epsilon zeta.'),
      ], parserVersion: 1);

      final presentation = _resolved();
      final layout = ValueNotifier<ScrollLayout?>(
        measureRun(
          tokens: text.tokens,
          index: 2,
          style: readingTextStyle(presentation),
          styleKey: scrollStyleKeyFor(presentation.config),
          chapterStarts: const {3},
          isParagraphEnd: text.isParagraphEndAt,
        ),
      );

      await tester.pumpWidget(_surface(presentation, layout: layout));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_painter(tester).layout.value!.segments, isNotEmpty);
    });
  });
}
