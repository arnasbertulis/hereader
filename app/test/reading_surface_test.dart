import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/profile_edit_screen.dart';
import 'package:app/reading/profile_presentation.dart';
import 'package:app/reading/reader_screen.dart';
import 'package:app/reading/rsvp_view.dart';
import 'package:app/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

Future<String> _stamp() async => '0000000000001-00000-test';

PlaybackUpdate _showing(String word) => PlaybackUpdate(
  state: PlaybackState.paused,
  index: 0,
  token: Token(text: word, charOffset: 0),
);

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
  });

  group('the reader screen', () {
    late AppDatabase database;

    setUp(() => database = AppDatabase(NativeDatabase.memory()));
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

    setUp(() => database = AppDatabase(NativeDatabase.memory()));
    tearDown(() => database.close());

    Widget editor(ReadingProfile profile, {Brightness app = Brightness.light}) =>
        MaterialApp(
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
      await tester.pumpWidget(editor(_profile(), app: Brightness.dark));
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(profileFollowAppKey);

      // Named rather than left to default. `scrollUntilVisible` resolves its
      // own default to the single Scrollable in the tree, and the name field
      // builds an EditableText with a Scrollable of its own, so the default
      // matches two and throws before it scrolls anything. The list is the
      // outer one, so it comes first.
      await tester.scrollUntilVisible(
        switchFinder,
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);

      SegmentedButton<Polarity> polarityControl() =>
          tester.widget<SegmentedButton<Polarity>>(
            find.byType(SegmentedButton<Polarity>),
          );

      // Following, so the control shows the side the app put it on and takes
      // no input.
      expect(polarityControl().selected, {Polarity.lightOnDark});
      expect(polarityControl().onSelectionChanged, isNull);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);
      expect(polarityControl().selected, {Polarity.lightOnDark});
      expect(polarityControl().onSelectionChanged, isNotNull);

      await _disposeTree(tester);
    });
  });
}
