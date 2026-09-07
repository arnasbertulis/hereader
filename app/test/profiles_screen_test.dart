import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/info_dot.dart';
import 'package:app/reading/profiles_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repository;
  late int stamps;

  Future<String> issueStamp() async {
    stamps++;
    return '000000000000$stamps-00000-test';
  }

  setUp(() {
    db = AppDatabase(testExecutor());
    repository = LibraryRepository(db);
    stamps = 0;
  });

  tearDown(() => db.close());

  Finder infoDotFor(String semanticLabel) => find.byWidgetPredicate(
    (w) => w is InfoDot && w.semanticLabel == semanticLabel,
  );

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilesScreen(repository: repository, issueStamp: issueStamp),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The Drift stream subscriptions `watchActiveProfile`/`watchProfiles`
  // leave a Timer scheduled; unmounting and pumping past it here is what
  // clears it before teardown, or the framework reports a leaked timer —
  // see .claude/rules/app.md and home_screen_test.dart's `_disposeTree`.
  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  group('Your profiles', () {
    testWidgets('prints no explanation by default, only the (i)', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(
        find.textContaining('Your profiles follow you between devices'),
        findsNothing,
      );
      expect(infoDotFor('About your profiles'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('reveals the explanation on tap', (tester) async {
      await pumpScreen(tester);

      await tester.tap(infoDotFor('About your profiles'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Your profiles follow you between devices'),
        findsOneWidget,
      );

      await disposeTree(tester);
    });
  });
}
