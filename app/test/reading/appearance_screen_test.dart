import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/appearance_screen.dart';
import 'package:app/reading/info_dot.dart';
import 'package:app/theme/appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_database.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repo;
  late AppearanceController appearance;

  Future<String> issueStamp() async {
    return '000000000000-00000-test';
  }

  setUp(() {
    db = AppDatabase(testExecutor());
    repo = LibraryRepository(db);
    appearance = AppearanceController(repository: repo, issueStamp: issueStamp);
  });

  tearDown(() {
    appearance.dispose();
    db.close();
  });

  group('Appearance screen', () {
    testWidgets('InfoDot is present in the AppBar actions', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: AppearanceScreen(controller: appearance)),
      );

      final appBarInfoDot = find.descendant(
        of: find.byType(AppBar),
        matching: find.byKey(appearanceInfoDotKey),
      );
      expect(
        appBarInfoDot,
        findsOneWidget,
        reason: 'The screen-summary InfoDot should be in the AppBar actions',
      );
      expect(
        tester.widget<InfoDot>(appBarInfoDot).semanticLabel,
        equals('About appearance settings'),
      );
    });

    testWidgets('Contrast header has no InfoDot attached', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: AppearanceScreen(controller: appearance)),
      );

      final contrastHeader = find.byKey(appearanceContrastHeaderKey);
      expect(contrastHeader, findsOneWidget);

      expect(
        find.descendant(of: contrastHeader, matching: find.byType(InfoDot)),
        findsNothing,
        reason: 'The Contrast section header should carry no InfoDot',
      );
    });
  });
}
