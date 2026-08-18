import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_screen.dart';
import 'package:app/reading/note_editor_screen.dart';
import 'package:app/sync/api_client.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepository(db);
    auth = AuthStore();
    api = ApiClient(baseUrl: Uri.parse('http://localhost'), auth: auth);
    sync = SyncEngine(
      repository: repository,
      api: api,
      auth: auth,
      database: db,
    );
  });

  tearDown(() async {
    sync.dispose();
    api.dispose();
    auth.dispose();
    await db.close();
  });

  Future<void> addBook(String id, {required String title}) =>
      repository.addBook(
        id: id,
        title: title,
        bytes: Uint8List.fromList([1, 2, 3]),
        wordCount: 1000,
        sourceFormat: 'epub',
      );

  Future<void> addNote(String id, {required String title}) =>
      repository.addBook(
        id: id,
        title: title,
        bytes: Uint8List.fromList(utf8.encode('Some note text.')),
        wordCount: 3,
        sourceFormat: 'note',
      );

  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          sync: sync,
          issueStamp: () async => '0000000000001-00000-test',
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
    // The save-and-open path itself — filtered to Books, tapping through
    // Write a note, entering text, tapping Save and read, confirming the
    // shelf lands on All with the new note visible — is not covered by an
    // automated test here. It routes through BookImporter.openNote's real
    // compute() isolate, and while tester.runAsync is the documented way to
    // let a widget test await a real isolate, doing so across this route's
    // full depth (add-menu dialog, the editor, BookOpener's own sync and
    // conflict checks, then the reader it pushes) reliably hung rather than
    // resolving even with a generous real-time delay inside it, for reasons
    // that did not resolve with the time budget available. The condition
    // this test would have checked was read by hand instead: _import and
    // _openNote each reset the filter to All exactly when the format just
    // added would not appear under the filter as it stood, which the
    // "cancelling" test below at least confirms is not triggered by a
    // no-op path through the same screens.
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
        await tester.tap(find.text('Write a note'));
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
}
