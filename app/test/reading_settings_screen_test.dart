import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
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

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ReadingSettingsScreen(display: display)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Keys while reading'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
  }

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
