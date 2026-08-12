import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/profile_edit_screen.dart';
import 'package:app/reading/profile_presentation.dart';
import 'package:app/reading/rsvp_view.dart';

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
        final presentation = PresentationConfig(polarity: polarity);

        await tester.pumpWidget(
          MaterialApp(
            home: RsvpView(
              update: _showing('reading'),
              presentation: presentation,
            ),
          ),
        );

        final surface = tester
            .widgetList<ColoredBox>(
              find.descendant(
                of: find.byType(RsvpView),
                matching: find.byType(ColoredBox),
              ),
            )
            .first;

        expect(surface.color, colorOf(surfaceArgbFor(presentation)));

        final word = tester.widget<Text>(find.text('reading'));
        expect(word.style?.color, colorOf(inkArgbFor(polarity)));
      });
    }

    testWidgets('a tint overrides the polarity surface', (tester) async {
      const presentation = PresentationConfig(tintArgb: 0xFF102030);

      await tester.pumpWidget(
        MaterialApp(
          home: RsvpView(
            update: _showing('reading'),
            presentation: presentation,
          ),
        ),
      );

      final surface = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(RsvpView),
              matching: find.byType(ColoredBox),
            ),
          )
          .first;

      expect(surface.color, const Color(0xFF102030));
    });
  });

  group('the settings preview', () {
    late AppDatabase database;

    setUp(() => database = AppDatabase(NativeDatabase.memory()));
    tearDown(() => database.close());

    Widget editor(ReadingProfile profile) => MaterialApp(
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
  });
}
