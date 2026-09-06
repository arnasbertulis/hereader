import 'dart:async';
import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/add_menu.dart';
import 'package:app/reading/add_menu_dispatcher.dart';
import 'package:app/reading/book_importer.dart';
import 'package:app/reading/free_books_screen.dart';
import 'package:app/reading/note_editor_screen.dart';
import 'package:app/reading/paste_reader_screen.dart';
import 'package:app/sync/api_client.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'test_database.dart';

/// This is the only place that answers "does Paste open the paste screen" —
/// see #302. A minimal tree, one [Navigator], no shelf: each test asserts
/// that one answer opens the screen it should, or in [AddChoice.epub]'s
/// case, that it imports without opening one at all.
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

  AddMenuDispatcher dispatcher({BookImporter? importer}) => AddMenuDispatcher(
    repository: repository,
    sync: sync,
    catalogue: catalogue,
    importer: importer,
  );

  /// A `Builder`'s context, inside a `MaterialApp` and a `Scaffold`, so
  /// `Navigator.of` and `showDialog` have somewhere real to push and show
  /// onto, and a parse failure's `ScaffoldMessenger.showSnackBar` has a
  /// descendant Scaffold to present to.
  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return captured;
  }

  testWidgets('freeBooks opens Free books', (tester) async {
    final context = await pumpContext(tester);

    await dispatcher().act(context, AddChoice.freeBooks);
    await tester.pumpAndSettle();

    expect(find.byType(FreeBooksScreen), findsOneWidget);
  });

  testWidgets('note opens the note editor', (tester) async {
    final context = await pumpContext(tester);

    await dispatcher().act(context, AddChoice.note);
    await tester.pumpAndSettle();

    expect(find.byType(NoteEditorScreen), findsOneWidget);
  });

  testWidgets('paste opens the paste screen', (tester) async {
    final context = await pumpContext(tester);

    await dispatcher().act(context, AddChoice.paste);
    await tester.pumpAndSettle();

    expect(find.byType(PasteReaderScreen), findsOneWidget);
  });

  testWidgets('epub delegates to the importer without opening a screen', (
    tester,
  ) async {
    final context = await pumpContext(tester);
    final importer = _RecordingImporter(repository: repository);

    await dispatcher(importer: importer).act(context, AddChoice.epub);
    await tester.pumpAndSettle();

    expect(importer.called, isTrue);
    expect(find.byType(FreeBooksScreen), findsNothing);
    expect(find.byType(NoteEditorScreen), findsNothing);
    expect(find.byType(PasteReaderScreen), findsNothing);
  });

  testWidgets(
    'onBusy fires true then false for epub, once bytes exist, and never on '
    'a cancel (#269)',
    (tester) async {
      final context = await pumpContext(tester);
      final calls = <bool>[];

      await dispatcher(
        importer: BookImporter(
          repository: repository,
          pickBytes: () async => null,
        ),
      ).act(context, AddChoice.epub, onBusy: calls.add);
      await tester.pumpAndSettle();

      expect(calls, isEmpty);

      await dispatcher(
        importer: _RecordingImporter(repository: repository),
      ).act(context, AddChoice.epub, onBusy: calls.add);
      await tester.pumpAndSettle();

      expect(calls, [true, false]);
    },
  );

  testWidgets('onBusy fires true then false for a parse failure', (
    tester,
  ) async {
    final context = await pumpContext(tester);
    final calls = <bool>[];

    await dispatcher(
      importer: BookImporter(
        repository: repository,
        pickBytes: () async => Uint8List.fromList([1, 2, 3]),
        parser: const ThrowingBookParser(),
      ),
    ).act(context, AddChoice.epub, onBusy: calls.add);
    await tester.pumpAndSettle();

    expect(calls, [true, false]);
  });

  testWidgets('onBusy is never called for the other three choices', (
    tester,
  ) async {
    final context = await pumpContext(tester);
    final calls = <bool>[];

    for (final choice in [
      AddChoice.freeBooks,
      AddChoice.paste,
      AddChoice.note,
    ]) {
      await dispatcher().act(context, choice, onBusy: calls.add);
      await tester.pumpAndSettle();
    }

    expect(calls, isEmpty);
  });

  testWidgets('showAndAct opens the menu and acts on the tapped option', (
    tester,
  ) async {
    final context = await pumpContext(tester);

    unawaited(dispatcher().showAndAct(context));
    await tester.pumpAndSettle();

    // The dialog outgrows the default 800x600 test surface at this text
    // scale, the same way it does in library_grid_test.dart's equivalent tap.
    await tester.ensureVisible(find.byKey(addMenuPasteKey));
    await tester.tap(find.byKey(addMenuPasteKey));
    await tester.pumpAndSettle();

    expect(find.byType(PasteReaderScreen), findsOneWidget);
  });

  testWidgets('showAndAct does nothing when the menu is dismissed', (
    tester,
  ) async {
    final context = await pumpContext(tester);

    unawaited(dispatcher().showAndAct(context));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.byType(FreeBooksScreen), findsNothing);
    expect(find.byType(NoteEditorScreen), findsNothing);
    expect(find.byType(PasteReaderScreen), findsNothing);
  });
}

/// Records that the dispatcher called it, standing in for the real pick and
/// parse. `BookImporter` already has its own tests for what a real import
/// does; this only needs to confirm the dispatcher asks it to run.
class _RecordingImporter extends BookImporter {
  bool called = false;

  _RecordingImporter({required super.repository});

  @override
  Future<ImportOutcome> importPickedFile(
    BuildContext context, {
    VoidCallback? onPicked,
  }) async {
    called = true;
    onPicked?.call();
    return ImportOutcome.imported;
  }
}
