import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/note_editor_screen.dart';
import 'package:app/sync/api_client.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'test_database.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repository;
  late AuthStore auth;
  late ApiClient api;
  late SyncEngine sync;

  setUp(() async {
    db = AppDatabase(testExecutor());
    repository = LibraryRepository(db);
    auth = AuthStore(storage: FakeSecureStorage());
    api = ApiClient(baseUrl: Uri.parse('http://localhost'), auth: auth);
    sync = SyncEngine(
      repository: repository,
      api: api,
      auth: auth,
      database: db,
    );
    await sync.start();
  });

  tearDown(() async {
    sync.dispose();
    api.dispose();
    auth.dispose();
    await db.close();
  });

  // A button that pushes NoteEditorScreen, rather than pumping it directly:
  // the screen's own back-arrow guard needs a real route to intercept, which
  // only exists once it is pushed onto a Navigator.
  Future<void> pushEditor(
    WidgetTester tester, {
    String? noteId,
    String title = '',
    String body = '',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => NoteEditorScreen(
                      repository: repository,
                      sync: sync,
                      noteId: noteId,
                      initialTitle: title,
                      initialBody: body,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('note body field', () {
    testWidgets('carries a visible label, not only a hint', (tester) async {
      await pushEditor(tester, noteId: 'n1', title: 'Mine', body: 'Some text');

      final field = tester.widget<TextField>(find.byType(TextField).last);
      expect(field.decoration?.labelText, 'Note');
    });
  });

  group('leaving with unsaved changes', () {
    testWidgets('an unedited note pops without asking', (tester) async {
      await pushEditor(tester, noteId: 'n1', title: 'Mine', body: 'Some text');

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(NoteEditorScreen), findsNothing);
      expect(find.text('Discard this note?'), findsNothing);
    });

    testWidgets('a fresh, untouched note pops without asking', (tester) async {
      await pushEditor(tester);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(NoteEditorScreen), findsNothing);
      expect(find.text('Discard this note?'), findsNothing);
    });

    testWidgets('an edited note asks before the back arrow discards it', (
      tester,
    ) async {
      await pushEditor(tester, noteId: 'n1', title: 'Mine', body: 'Some text');

      await tester.enterText(find.byType(TextField).last, 'Changed text');
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Discard this note?'), findsOneWidget);
      expect(find.byType(NoteEditorScreen), findsOneWidget);
    });

    testWidgets('"Keep editing" leaves the note open with the change intact', (
      tester,
    ) async {
      await pushEditor(tester, noteId: 'n1', title: 'Mine', body: 'Some text');

      await tester.enterText(find.byType(TextField).last, 'Changed text');
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(noteEditorKeepEditingButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(NoteEditorScreen), findsOneWidget);
      expect(find.text('Changed text'), findsOneWidget);
    });

    testWidgets('"Discard" pops without writing the change', (tester) async {
      await pushEditor(tester, noteId: 'n1', title: 'Mine', body: 'Some text');

      await tester.enterText(find.byType(TextField).last, 'Changed text');
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(noteEditorDiscardButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(NoteEditorScreen), findsNothing);
      expect(await repository.storedBookOf('n1'), isNull);
    });
  });

  group('save controls', () {
    // The full save path runs BookParser.openNote through compute(), which
    // spawns an isolate a widget test has no cheap way to wait on (see
    // app/README.md's note on this, and the StubBookParser workaround used
    // where a lower layer already made the parser injectable). NoteEditorScreen
    // builds its own `const BookParser()` inline with no seam to stub it, so
    // coverage here stops at what a rendered tree can confirm without tapping
    // through to a save: both controls exist, wired to different callbacks.
    testWidgets('offers Save alongside Save and read', (tester) async {
      await pushEditor(tester, noteId: 'n1', title: 'Mine', body: 'Some text');

      expect(find.byKey(noteEditorSaveButtonKey), findsOneWidget);
      expect(find.byKey(noteEditorSaveAndReadButtonKey), findsOneWidget);

      final saveOnPressed = tester
          .widget<OutlinedButton>(find.byKey(noteEditorSaveButtonKey))
          .onPressed;
      final saveAndReadOnPressed = tester
          .widget<FilledButton>(find.byKey(noteEditorSaveAndReadButtonKey))
          .onPressed;
      expect(saveOnPressed, isNotNull);
      expect(saveAndReadOnPressed, isNotNull);
      expect(saveOnPressed, isNot(same(saveAndReadOnPressed)));
    });

    testWidgets('both save controls are disabled until there is text', (
      tester,
    ) async {
      await pushEditor(tester);

      expect(
        tester
            .widget<OutlinedButton>(find.byKey(noteEditorSaveButtonKey))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(noteEditorSaveAndReadButtonKey))
            .onPressed,
        isNull,
      );

      await tester.enterText(find.byType(TextField).last, 'New note text');
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<OutlinedButton>(find.byKey(noteEditorSaveButtonKey))
            .onPressed,
        isNotNull,
      );
    });
  });
}
