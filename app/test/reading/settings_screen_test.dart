import 'package:app/data/database.dart' hide PositionConflict;
import 'package:app/data/library_repository.dart';
import 'package:app/reading/reading_display.dart';
import 'package:app/reading/settings_screen.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/sign_in_screen.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:app/theme/appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';
import '../test_database.dart';

/// The account block that replaced the old Account and Sync screens (ADR
/// 0034 §2, issue #356): are you signed in, and is your reading backed up,
/// as one row at the top of Settings.
void main() {
  late AppDatabase db;
  late LibraryRepository repository;
  late AuthStore auth;
  late FakeApi api;
  late SyncEngine sync;
  late AppearanceController appearance;
  late ReadingDisplayController display;

  setUp(() async {
    db = AppDatabase(testExecutor());
    repository = LibraryRepository(db);
    auth = AuthStore(storage: FakeSecureStorage());
    api = FakeApi(auth: auth);
    sync = SyncEngine(
      repository: repository,
      api: api,
      auth: auth,
      database: db,
    );
    // Not started: start() arms a 5-minute Timer.periodic that would still
    // be pending when flutter_test checks for leaked timers at the end of
    // each test, since tearDown (where sync.dispose() cancels it) runs after
    // that check. None of these tests need the periodic sync loop — they
    // drive syncNow() and the session stream directly.
    appearance = AppearanceController(
      repository: repository,
      issueStamp: sync.issueStamp,
    );
    await appearance.restore();
    display = ReadingDisplayController(
      repository: repository,
      issueStamp: sync.issueStamp,
    );
    await display.restore();
  });

  tearDown(() async {
    sync.dispose();
    api.dispose();
    auth.dispose();
    await db.close();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          repository: repository,
          issueStamp: sync.issueStamp,
          appearance: appearance,
          display: display,
          api: api,
          sync: sync,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The Drift stream subscription `watchProfiles` leaves a Timer scheduled;
  // unmounting and pumping past it here is what clears it before teardown,
  // or the framework reports a leaked timer — see .claude/rules/app.md and
  // home_screen_test.dart's `_disposeTree`.
  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  group('signed out', () {
    testWidgets('states not signed in and how to fix it, not a bare label', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Not signed in'), findsOneWidget);
      expect(find.text('Sign in to carry your place'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('the sync button is disabled', (tester) async {
      await pumpScreen(tester);

      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.onPressed, isNull);

      await disposeTree(tester);
    });

    testWidgets('tapping the row opens sign-in, not a pushed account screen', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Not signed in'));
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsOneWidget);

      await disposeTree(tester);
    });
  });

  group('signed in', () {
    setUp(() async {
      await auth.save(
        const Session(accessToken: 'access', refreshToken: 'refresh'),
      );
    });

    testWidgets('states signed in, and that reading has never synced yet', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Signed in'), findsOneWidget);
      expect(find.text('Not synced on this device yet'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('tapping the sync button runs a sync', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(api.pulledSince, isNotEmpty);

      await disposeTree(tester);
    });

    testWidgets('tapping the row opens a sheet with sign out, not a push', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Signed in'));
      await tester.pumpAndSettle();

      expect(find.text('Sign out'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('signing out from the sheet clears the session', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Signed in'));
      await tester.pumpAndSettle();
      // Opens the confirm dialog from the sheet's own button, which stays in
      // the tree under the dialog — so 'Sign out' now matches two widgets,
      // and each tap must name which one.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(auth.current, isNull);
      expect(find.text('Not signed in'), findsOneWidget);

      await disposeTree(tester);
    });
  });
}
