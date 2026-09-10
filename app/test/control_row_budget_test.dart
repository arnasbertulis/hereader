import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/appearance_screen.dart';
import 'package:app/reading/control_row.dart';
import 'package:app/reading/profiles_screen.dart';
import 'package:app/reading/reading_display.dart';
import 'package:app/reading/reading_settings_screen.dart';
import 'package:app/reading/section_header.dart';
import 'package:app/reading/settings_screen.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:app/theme/appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'test_database.dart';

/// ADR 0036: every chrome screen budgets its prose in blocks — a control
/// gets its label and at most one supporting sentence, a section gets its
/// header and at most one supporting sentence, nothing else is printed.
///
/// This walks the Settings screens converted onto [ControlRow] at text scale
/// 1.0 and 2.0, checking two things a reviewer would otherwise have to
/// remember on every future change: every [ListTile] on the screen was built
/// by a [ControlRow] (never a bare one carrying a second sentence in a
/// `Widget` subtitle, which a `String` field cannot do), and every
/// sentence-shaped piece of text on the screen lives inside a [ControlRow]
/// or a [SectionHeader] rather than free-standing on the page.
void main() {
  for (final scale in [1.0, 2.0]) {
    group('at text scale $scale', () {
      Future<void> pumpAtScale(WidgetTester tester, Widget home) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: home,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      void expectEveryListTileIsAControlRow(WidgetTester tester) {
        expect(
          find.byType(ListTile).evaluate().length,
          find.byType(ControlRow).evaluate().length,
          reason:
              'a bare ListTile on a covered screen can carry a Widget '
              'subtitle — only ControlRow, whose supporting line is a '
              'String, is allowed here',
        );
      }

      // "Sentence-shaped": more than four words, or ends with a full stop.
      // A button's own label ("Sign out") and a value chip ("16 pt") both
      // fail this on purpose — the budget is about explanatory prose, not
      // every string on screen.
      bool looksLikeASentence(String text) =>
          text.trim().endsWith('.') || text.trim().split(' ').length > 4;

      void expectNoStrayProse(WidgetTester tester) {
        for (final element in find.byType(Text).evaluate()) {
          final text = (element.widget as Text).data;
          if (text == null || !looksLikeASentence(text)) continue;

          var budgeted = false;
          element.visitAncestorElements((ancestor) {
            if (ancestor.widget is ControlRow ||
                ancestor.widget is SectionHeader) {
              budgeted = true;
              return false;
            }
            return true;
          });

          expect(
            budgeted,
            isTrue,
            reason:
                'prose outside a ControlRow/SectionHeader on a covered '
                'screen: "$text"',
          );
        }
      }

      testWidgets('Settings index', (tester) async {
        final db = AppDatabase(testExecutor());
        final repository = LibraryRepository(db);
        final auth = AuthStore(storage: FakeSecureStorage());
        final api = FakeApi(auth: auth);
        final sync = SyncEngine(
          repository: repository,
          api: api,
          auth: auth,
          database: db,
        );
        final appearance = AppearanceController(
          repository: repository,
          issueStamp: sync.issueStamp,
        );
        await appearance.restore();
        final display = ReadingDisplayController(
          repository: repository,
          issueStamp: sync.issueStamp,
        );
        await display.restore();

        await pumpAtScale(
          tester,
          SettingsScreen(
            repository: repository,
            issueStamp: sync.issueStamp,
            appearance: appearance,
            display: display,
            api: api,
            sync: sync,
          ),
        );

        expectEveryListTileIsAControlRow(tester);
        expectNoStrayProse(tester);

        // Drift's watchProfiles subscription leaves a Timer scheduled; unmount
        // and pump past it before teardown — see settings_screen_test.dart.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 1));
        sync.dispose();
        api.dispose();
        auth.dispose();
        await db.close();
      });

      testWidgets('Reading', (tester) async {
        final db = AppDatabase(testExecutor());
        final display = ReadingDisplayController(
          repository: LibraryRepository(db),
          issueStamp: () async => '2024-01-01T00:00:00.000Z-0000-test',
        );
        await display.restore();

        await pumpAtScale(tester, ReadingSettingsScreen(display: display));

        expectEveryListTileIsAControlRow(tester);
        expectNoStrayProse(tester);

        await db.close();
      });

      testWidgets('Appearance', (tester) async {
        final db = AppDatabase(testExecutor());
        final repo = LibraryRepository(db);
        final appearance = AppearanceController(
          repository: repo,
          issueStamp: () async => '000000000000-00000-test',
        );

        await pumpAtScale(tester, AppearanceScreen(controller: appearance));

        expectEveryListTileIsAControlRow(tester);
        expectNoStrayProse(tester);

        appearance.dispose();
        await db.close();
      });

      testWidgets('Reading profiles', (tester) async {
        final db = AppDatabase(testExecutor());
        final repository = LibraryRepository(db);

        await pumpAtScale(
          tester,
          ProfilesScreen(
            repository: repository,
            issueStamp: () async => '000000000001-00000-test',
          ),
        );

        expectEveryListTileIsAControlRow(tester);
        expectNoStrayProse(tester);

        await db.close();
      });
    });
  }
}
