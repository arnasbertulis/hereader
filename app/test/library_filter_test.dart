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

/// Pumps in bounded real-time steps until [finder] finds something.
///
/// The save-and-open path shows an indeterminate spinner while busy, and an
/// indeterminate spinner's own animation keeps requesting frames forever —
/// exactly what makes `pumpAndSettle` time out rather than return once the
/// real `compute()` work behind it actually finishes. Must run inside
/// `tester.runAsync`, the same real zone as the async work it waits on.
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxTries = 100,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
  throw StateError('Timed out waiting for $finder');
}

/// The pop transition back off [NoteEditorScreen] keeps its `EditableText`
/// mounted for a beat, and `EditableText` is itself a match for `find.text`,
/// so a shelf assertion taken mid-transition can find the new title twice —
/// once as the tile's own [Text], once as the editor's field on its way out.
Future<void> _pumpUntilExactlyOne(
  WidgetTester tester,
  Finder finder, {
  int maxTries = 100,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (finder.evaluate().length == 1) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
  throw StateError('Timed out waiting for exactly one $finder');
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

  group('writing a note resets a mismatched filter', () {
    // The save-and-open path runs BookParser.openNote and
    // BookParser.reopenStored on the real compute() isolate and pushes a
    // real ReaderScreen, so every test below drives the tap and the
    // subsequent pumps inside tester.runAsync, which escapes the FakeAsync
    // zone testWidgets otherwise runs in. Backing out through the reader's
    // own "Back to library" control (rather than popping the route directly)
    // is what lets BookOpener.open's own await resolve, which is what lets
    // NoteEditorScreen pop(true), which is what lets the filter-reset rule
    // run at all.
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

    testWidgets(
      'filtered to Books, a saved note shows the shelf that contains it',
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

        await tester.enterText(find.byType(TextField).first, 'A New Note');
        await tester.enterText(
          find.byType(TextField).last,
          'Something worth reading.',
        );
        await tester.pump();

        await tester.runAsync(() async {
          await tester.tap(find.text('Save and read'));
          await _pumpUntilFound(tester, find.byTooltip('Back to library'));
          await tester.pump(const Duration(milliseconds: 300));

          // The reader is open; leaving it is what lets BookOpener.open's
          // own await resolve so the save-and-open chain can finish.
          await tester.tap(find.byTooltip('Back to library'));
          await _pumpUntilFound(tester, find.byKey(libraryAddButtonKey));
          await _pumpUntilExactlyOne(tester, find.text('A New Note'));
        });

        expect(find.text('All'), findsOneWidget);
        expect(find.text('Books'), findsNothing);
        expect(find.text('A New Note'), findsOneWidget);

        await _disposeTree(tester);
      },
    );

    testWidgets('filtered to Notes, a saved note leaves the filter alone', (
      tester,
    ) async {
      await addNote('note-1', title: 'An Old Note');

      await pump(tester);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notes').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(libraryAddButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(addMenuNoteKey));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'A New Note');
      await tester.enterText(
        find.byType(TextField).last,
        'Something else worth reading.',
      );
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.text('Save and read'));
        await _pumpUntilFound(tester, find.byTooltip('Back to library'));
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.byTooltip('Back to library'));
        await _pumpUntilFound(tester, find.byKey(libraryAddButtonKey));
        await _pumpUntilExactlyOne(tester, find.text('A New Note'));
      });

      // Still Notes: the format that landed is exactly the one this
      // filter already shows, so the rule this ticket exists to unify
      // never fires.
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('All'), findsNothing);
      expect(find.text('A New Note'), findsOneWidget);

      await _disposeTree(tester);
    });
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

    testWidgets(
      'filtered to Books, a successful import leaves the filter alone',
      (tester) async {
        await addBook('book-1', title: 'Romeo and Juliet');

        await pump(
          tester,
          bookImporter: BookImporter(
            repository: repository,
            pickBytes: () async => Uint8List.fromList([1, 2, 3]),
            parser: StubBookParser(
              fixtureBook(id: 'epub-2', title: 'Pride and Prejudice'),
            ),
          ),
        );

        await tester.tap(find.text('All'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Books').last);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(libraryAddButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(addMenuEpubKey));
        await tester.pumpAndSettle();

        // Still Books: the format that landed is exactly the one this filter
        // already shows, so the rule this ticket exists to unify never fires.
        expect(find.text('Books'), findsOneWidget);
        expect(find.text('All'), findsNothing);
        expect(find.text('Pride and Prejudice'), findsOneWidget);

        await _disposeTree(tester);
      },
    );

    testWidgets(
      'a cancelled import leaves the filter alone, shows no message and '
      'does not repaint the shelf',
      (tester) async {
        await addNote('note-1', title: 'A Note');

        await pump(
          tester,
          bookImporter: BookImporter(
            repository: repository,
            // A null pick is the file dialog reporting the reader backed
            // out. importPickedFile reports cancelled without ever calling
            // the parser, so there is nothing for it to build a book from.
            pickBytes: () async => null,
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
        expect(find.byType(SnackBar), findsNothing);
        // The shelf still shows exactly the note it started with — nothing
        // else landed for a cancelled pick to have made visible.
        expect(find.text('A Note'), findsOneWidget);

        await _disposeTree(tester);
      },
    );
  });
}
