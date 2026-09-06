import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/add_menu.dart';
import 'package:app/reading/add_menu_dispatcher.dart';
import 'package:app/reading/book_importer.dart';
import 'package:app/reading/free_books_screen.dart';
import 'package:app/reading/home_screen.dart';
import 'package:app/reading/note_editor_screen.dart';
import 'package:app/reading/paste_reader_screen.dart';
import 'package:app/reading/reading_display.dart';
import 'package:app/sync/api_client.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'test_database.dart';

/// Drift schedules a zero-duration timer when a query stream is cancelled.
/// Left to teardown it is never pumped and the framework reports a leaked
/// timer, so the pump has to advance the clock.
Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late AppDatabase db;
  late LibraryRepository repository;
  late AuthStore auth;
  late ApiClient api;
  late SyncEngine sync;
  late FakeCatalogueClient catalogue;

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
    catalogue = FakeCatalogueClient();
  });

  tearDown(() async {
    sync.dispose();
    api.dispose();
    auth.dispose();
    await db.close();
  });

  Future<void> pump(
    WidgetTester tester, {
    AddMenuDispatcher? dispatcher,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          repository: repository,
          sync: sync,
          onSeeAll: () {},
          display: ReadingDisplayController(
            repository: repository,
            issueStamp: () async => '0000000000001-00000-test',
          ),
          catalogue: catalogue,
          dispatcher: dispatcher,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAddMenu(WidgetTester tester) async {
    await tester.tap(find.text('Add something to read'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'picking an EPUB from the add menu shows it in the continue tile',
    (tester) async {
      await pump(
        tester,
        dispatcher: AddMenuDispatcher(
          repository: repository,
          sync: sync,
          catalogue: catalogue,
          importer: BookImporter(
            repository: repository,
            pickBytes: () async => Uint8List.fromList([1, 2, 3]),
            parser: StubBookParser(
              fixtureBook(id: 'epub-1', title: 'Pride and Prejudice'),
            ),
          ),
        ),
      );

      await openAddMenu(tester);
      await tester.tap(find.byKey(addMenuEpubKey));
      await tester.pumpAndSettle();

      expect(find.byKey(homeContinueTileKey), findsOneWidget);
      expect(find.text('Pride and Prejudice'), findsOneWidget);

      await _disposeTree(tester);
    },
  );

  testWidgets('the continue tile spinner clears once the import lands', (
    tester,
  ) async {
    await pump(
      tester,
      dispatcher: AddMenuDispatcher(
        repository: repository,
        sync: sync,
        catalogue: catalogue,
        importer: BookImporter(
          repository: repository,
          pickBytes: () async => Uint8List.fromList([1, 2, 3]),
          parser: StubBookParser(
            fixtureBook(id: 'epub-1', title: 'Pride and Prejudice'),
          ),
        ),
      ),
    );

    await openAddMenu(tester);
    await tester.tap(find.byKey(addMenuEpubKey));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(homeContinueTileKey),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );

    await _disposeTree(tester);
  });

  // These three, plus the EPUB test above, are the "test that says so for all
  // four" #303 asks for: Home opens the same dispatcher the Library does
  // (add_menu_dispatcher_test.dart), so tapping each option from Home's own
  // menu must land on the same screen type the Library's does.
  testWidgets('Free books opens the same screen the Library opens', (
    tester,
  ) async {
    await pump(tester);

    await openAddMenu(tester);
    await tester.tap(find.byKey(addMenuFreeBooksKey));
    await tester.pumpAndSettle();

    expect(find.byType(FreeBooksScreen), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('Note opens the same screen the Library opens', (tester) async {
    await pump(tester);

    await openAddMenu(tester);
    await tester.tap(find.byKey(addMenuNoteKey));
    await tester.pumpAndSettle();

    expect(find.byType(NoteEditorScreen), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('Paste opens the same screen the Library opens', (tester) async {
    await pump(tester);

    await openAddMenu(tester);
    // The dialog outgrows this test surface at this text scale, the same way
    // it does in add_menu_dispatcher_test.dart's equivalent tap.
    await tester.ensureVisible(find.byKey(addMenuPasteKey));
    await tester.tap(find.byKey(addMenuPasteKey));
    await tester.pumpAndSettle();

    expect(find.byType(PasteReaderScreen), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets(
    'cancelling the file chooser never disables the add button (#269)',
    (tester) async {
      await pump(
        tester,
        dispatcher: AddMenuDispatcher(
          repository: repository,
          sync: sync,
          catalogue: catalogue,
          importer: BookImporter(
            repository: repository,
            pickBytes: () async => null,
            parser: StubBookParser(
              fixtureBook(id: 'epub-1', title: 'Pride and Prejudice'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Add something to read'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(addMenuEpubKey));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add something to read'),
      );
      expect(button.onPressed, isNotNull);

      await _disposeTree(tester);
    },
  );
}
