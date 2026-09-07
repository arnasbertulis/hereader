import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/info_dot.dart';
import 'package:app/reading/reading_display.dart';
import 'package:app/reading/reading_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late ReadingDisplayController display;

  setUp(() async {
    db = AppDatabase(testExecutor());
    display = ReadingDisplayController(
      repository: LibraryRepository(db),
      issueStamp: () async => '2024-01-01T00:00:00.000Z-0000-test',
    );
    await display.restore();
  });

  tearDown(() async {
    await db.close();
  });

  // No scroll: leaves the top of the list, where Step/Time left/the
  // informational rows live, actually built. `ListView` is lazy, so a tile
  // scrolled past by [pumpScreen] would not be in the tree to find at all.
  Future<void> pumpTop(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ReadingSettingsScreen(display: display)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await pumpTop(tester);
    await tester.scrollUntilVisible(
      find.text('Keys while reading'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
  }

  Finder infoDotFor(String semanticLabel) => find.byWidgetPredicate(
    (w) => w is InfoDot && w.semanticLabel == semanticLabel,
  );

  group('Step', () {
    testWidgets('prints no explanation by default, only the (i)', (
      tester,
    ) async {
      await pumpTop(tester);

      expect(
        find.textContaining('Tapping the left or right quarter'),
        findsNothing,
      );
      expect(infoDotFor('About step'), findsOneWidget);
    });

    testWidgets('reveals the explanation on tap', (tester) async {
      await pumpTop(tester);

      await tester.tap(infoDotFor('About step'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Tapping the left or right quarter'),
        findsOneWidget,
      );
    });
  });

  group('Time left counts', () {
    testWidgets('prints no explanation by default, only the (i)', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(
        find.textContaining('On the home and library tiles'),
        findsNothing,
      );
      expect(infoDotFor('About time left counts'), findsOneWidget);
    });

    testWidgets('reveals the explanation on tap', (tester) async {
      await pumpScreen(tester);

      await tester.tap(infoDotFor('About time left counts'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('On the home and library tiles'),
        findsOneWidget,
      );
    });
  });

  group('informational rows', () {
    testWidgets('print no explanation by default, only the (i) each', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(
        find.textContaining('Every fifteen seconds while words are moving'),
        findsNothing,
      );
      expect(infoDotFor('About your place being saved'), findsOneWidget);
      expect(
        infoDotFor('About pausing when the app is hidden'),
        findsOneWidget,
      );
      expect(infoDotFor('About front matter'), findsOneWidget);
      expect(infoDotFor('About chapters'), findsOneWidget);
    });

    testWidgets('reveal their explanation on tap', (tester) async {
      await pumpScreen(tester);

      await tester.tap(infoDotFor('About your place being saved'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Every fifteen seconds while words are moving'),
        findsOneWidget,
      );
    });
  });

  group('Keys while reading', () {
    testWidgets('is collapsed by default, so no shortcut rows are shown', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Keys while reading'), findsOneWidget);
      expect(find.text('Start or pause'), findsNothing);
      expect(find.text('Close the book'), findsNothing);
    });

    testWidgets('opens on tap to reveal the shortcut rows', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Keys while reading'));
      await tester.pumpAndSettle();

      expect(find.text('Start or pause'), findsOneWidget);
      expect(find.text('Close the book'), findsOneWidget);
    });
  });
}
