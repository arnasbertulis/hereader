import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/add_menu.dart';
import 'package:app/reading/book_importer.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/library_screen.dart';
import 'package:app/reading/note_editor_screen.dart';
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

  Future<void> addBook(String id, {required String title}) =>
      repository.addBook(
        fixtureBook(id: id, title: title, wordCount: 1000),
        Uint8List.fromList([1, 2, 3]),
      );

  Future<void> addNote(String id, {required String title}) =>
      repository.addBook(
        fixtureBook(
          id: id,
          title: title,
          wordCount: 3,
          sourceFormat: BookSourceFormat.note,
        ),
        Uint8List.fromList(utf8.encode('Some note text.')),
      );

  Future<void> pump(WidgetTester tester, {BookImporter? bookImporter}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          sync: sync,
          display: ReadingDisplayController(
            repository: repository,
            issueStamp: () async => '0000000000001-00000-test',
          ),
          catalogue: catalogue,
          bookImporter: bookImporter,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a fully empty library shows no filter control', (tester) async {
    await pump(tester);

    expect(find.text('Nothing here yet'), findsOneWidget);
    // The filter reads "All" by default; its absence here is the point —
    // a filter with nothing under it takes its own escape route off the
    // screen, so it never renders before there is at least one book.
    expect(find.text('All'), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets('the filter defaults to All and shows both formats', (
    tester,
  ) async {
    await addBook('book-1', title: 'Romeo and Juliet');
    await addNote('note-1', title: 'My note');

    await pump(tester);

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Romeo and Juliet'), findsOneWidget);
    expect(find.text('My note'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('choosing Notes hides books and shows notes', (tester) async {
    await addBook('book-1', title: 'Romeo and Juliet');
    await addNote('note-1', title: 'My note');

    await pump(tester);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes').last);
    await tester.pumpAndSettle();

    expect(find.text('My note'), findsOneWidget);
    expect(find.text('Romeo and Juliet'), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets('choosing Books hides notes and shows books', (tester) async {
    await addBook('book-1', title: 'Romeo and Juliet');
    await addNote('note-1', title: 'My note');

    await pump(tester);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Books').last);
    await tester.pumpAndSettle();

    expect(find.text('Romeo and Juliet'), findsOneWidget);
    expect(find.text('My note'), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets(
    'Notes selected with none yet offers Write a note, not the general menu',
    (tester) async {
      await addBook('book-1', title: 'Romeo and Juliet');

      await pump(tester);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notes').last);
      await tester.pumpAndSettle();

      expect(find.text('No notes yet'), findsOneWidget);
      // The controls row survives the empty filtered state: All is still
      // one tap away rather than a dead end.
      expect(find.text('Notes'), findsOneWidget);

      await tester.tap(find.text('Write a note'));
      await tester.pumpAndSettle();

      expect(find.byType(NoteEditorScreen), findsOneWidget);
      // Not the three-way add dialog: the filter already said what kind of
      // thing is missing, so asking again would repeat the reader's own
      // choice back at them.
      expect(find.text('Add an EPUB'), findsNothing);

      await _disposeTree(tester);
    },
  );

  testWidgets(
    'Books selected with none yet offers Add an EPUB, not the general menu',
    (tester) async {
      await addNote('note-1', title: 'My note');

      await pump(tester);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Books').last);
      await tester.pumpAndSettle();

      expect(find.text('No EPUBs yet'), findsOneWidget);
      expect(find.text('Add an EPUB'), findsOneWidget);
      expect(find.text('Write a note'), findsNothing);

      await _disposeTree(tester);
    },
  );

  testWidgets('the filter choice survives a rebuild of the screen', (
    tester,
  ) async {
    await addBook('book-1', title: 'Romeo and Juliet');
    await addNote('note-1', title: 'My note');

    await pump(tester);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes').last);
    await tester.pumpAndSettle();

    await _disposeTree(tester);

    // A fresh LibraryScreen instance, the way switching tabs and back would
    // rebuild it, reading the same preference row rather than restarting at
    // the default.
    await pump(tester);

    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('My note'), findsOneWidget);
    expect(find.text('Romeo and Juliet'), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets("a note's tile menu offers Edit; an EPUB's does not", (
    tester,
  ) async {
    await addBook('book-1', title: 'Romeo and Juliet');
    await addNote('note-1', title: 'My note');

    await pump(tester);

    await tester.tap(find.byTooltip('More for My note'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More for Romeo and Juliet'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets('Edit opens the note pre-filled with its stored text', (
    tester,
  ) async {
    await addNote('note-1', title: 'My note');

    await pump(tester);

    await tester.tap(find.byTooltip('More for My note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit note'), findsOneWidget);
    expect(find.text('My note'), findsOneWidget);
    expect(find.text('Some note text.'), findsOneWidget);

    await _disposeTree(tester);
  });

  group('the floating add button', () {
    testWidgets('is hidden while the library is fully empty', (tester) async {
      await pump(tester);

      expect(find.byKey(libraryAddButtonKey), findsNothing);

      await _disposeTree(tester);
    });

    testWidgets(
      'stays visible even when the current filter has nothing under it',
      (tester) async {
        await addBook('book-1', title: 'Romeo and Juliet');

        await pump(tester);

        await tester.tap(find.text('All'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Notes').last);
        await tester.pumpAndSettle();

        // The shelf is empty under this filter, but the library itself is
        // not — _EmptyLibrary's single button is what disappears with the
        // library, not this one.
        expect(find.text('No notes yet'), findsOneWidget);
        expect(find.byKey(libraryAddButtonKey), findsOneWidget);

        await _disposeTree(tester);
      },
    );
  });

  group('a Book landing resets a mismatched filter, from any path', () {
    // LibraryScreen's own reset is not wired to any one add flow: it
    // subscribes to LibraryRepository.bookLanded (see _bookLanded in
    // initState) and reacts to the format that stream announces, whichever
    // write produced it. A direct repository.addBook call below stands in
    // for whichever path landed the Book — a file import, a Free books
    // download and a saved Note all resolve to that same call — so this is
    // the one place the general rule is exercised, rather than one test per
    // path.
    testWidgets(
      'a Book landed directly through the repository resets the filter',
      (tester) async {
        await addBook('book-1', title: 'Romeo and Juliet');

        await pump(tester);

        await tester.tap(find.text('All'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Books').last);
        await tester.pumpAndSettle();

        // Stands in for a Free books download: the same write, reached by a
        // different route than the file-picker path covered below.
        await addNote('note-1', title: 'My note');
        await tester.pumpAndSettle();

        expect(find.text('All'), findsOneWidget);
        expect(find.text('Books'), findsNothing);
        expect(find.text('My note'), findsOneWidget);

        await _disposeTree(tester);
      },
    );

    testWidgets(
      'a Book of a kind the filter already shows leaves the filter alone',
      (tester) async {
        await addBook('book-1', title: 'Romeo and Juliet');

        await pump(tester);

        await tester.tap(find.text('All'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Books').last);
        await tester.pumpAndSettle();

        await addBook('book-2', title: 'Hamlet');
        await tester.pumpAndSettle();

        expect(find.text('Books'), findsOneWidget);
        expect(find.text('All'), findsNothing);

        await _disposeTree(tester);
      },
    );

    testWidgets(
      're-adding a Book already on the shelf resets the filter the same '
      'way a new one does',
      (tester) async {
        await addBook('book-1', title: 'Romeo and Juliet');

        await pump(tester);

        await tester.tap(find.text('All'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Books').last);
        await tester.pumpAndSettle();

        await addNote('note-1', title: 'My note');
        await tester.pumpAndSettle();
        // Back to Books, so the second write below has a mismatched filter
        // of its own to reset.
        await tester.tap(find.text('All'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Books').last);
        await tester.pumpAndSettle();

        // The same id, reimported. insertOnConflictUpdate takes this path
        // rather than a fresh insert, but the reader gets the same
        // confirmation either way.
        await addNote('note-1', title: 'My note, edited');
        await tester.pumpAndSettle();

        expect(find.text('All'), findsOneWidget);
        expect(find.text('Books'), findsNothing);
        expect(find.text('My note, edited'), findsOneWidget);

        await _disposeTree(tester);
      },
    );

    testWidgets(
      'cancelling the editor without saving does not touch the filter',
      (tester) async {
        await addBook('book-1', title: 'Romeo and Juliet');

        await pump(tester);

        await tester.tap(find.text('All'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Books').last);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(libraryAddButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(addMenuNoteKey));
        await tester.pumpAndSettle();

        // Back out with nothing typed, rather than saving.
        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.text('Books'), findsOneWidget);
        expect(find.text('All'), findsNothing);

        await _disposeTree(tester);
      },
    );
  });

  group('adding an EPUB resets a mismatched filter', () {
    // A stubbed BookImporter, unlike BookParser.openNote above, never
    // touches compute()'s isolate, so the full add-menu-to-shelf path is
    // exercised here rather than read by hand.
    testWidgets(
      'a successful import shows the shelf that contains the new book',
      (tester) async {
        await addNote('note-1', title: 'A Note');

        await pump(
          tester,
          bookImporter: BookImporter(
            repository: repository,
            pickBytes: () async => Uint8List.fromList([1, 2, 3]),
            parser: StubBookParser(
              fixtureBook(id: 'epub-1', title: 'Pride and Prejudice'),
            ),
          ),
        );

        await tester.tap(find.text('All'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Notes').last);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(libraryAddButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(addMenuEpubKey));
        await tester.pumpAndSettle();

        expect(find.text('All'), findsOneWidget);
        expect(find.text('Notes'), findsNothing);
        expect(find.text('Pride and Prejudice'), findsOneWidget);

        await _disposeTree(tester);
      },
    );

    testWidgets('a failed import leaves the filter alone', (tester) async {
      await addNote('note-1', title: 'A Note');

      await pump(
        tester,
        bookImporter: BookImporter(
          repository: repository,
          pickBytes: () async => Uint8List.fromList([1, 2, 3]),
          parser: const ThrowingBookParser(),
        ),
      );

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notes').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(libraryAddButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(addMenuEpubKey));
      await tester.pumpAndSettle();

      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('All'), findsNothing);

      await _disposeTree(tester);
    });
  });
}
