import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/add_menu.dart';
import 'package:app/reading/book_cover.dart';
import 'package:app/reading/library_screen.dart';
import 'package:app/reading/paste_reader_screen.dart';
import 'package:app/reading/reading_display.dart';
import 'package:app/sync/api_client.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'fakes.dart';
import 'test_database.dart';

/// Drift schedules a zero-duration timer when a query stream is cancelled.
/// Left to teardown it is never pumped and the framework reports a leaked
/// timer, so the pump has to advance the clock.
Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<String> _stamp() async => '0000000000001-00000-test';

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

  Future<void> addBook(
    String id, {
    required String title,
    String? author,
    int wordCount = 1000,
    Uint8List? cover,
  }) => repository.addBook(
    fixtureBook(
      id: id,
      title: title,
      author: author,
      wordCount: wordCount,
      coverBytes: cover,
    ),
    Uint8List.fromList([1, 2, 3]),
  );

  Future<void> readTo(String id, int tokenIndex) => repository.savePosition(
    bookId: id,
    locator: Locator(blockId: 'block-1', charOffset: 0, parserVersion: 1),
    hlc: '0000000000001-00000-test',
    tokenIndex: tokenIndex,
  );

  Future<void> pump(WidgetTester tester, {double width = 900}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          sync: sync,
          display: ReadingDisplayController(
            repository: repository,
            issueStamp: _stamp,
          ),
          catalogue: catalogue,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a book never opened says so instead of showing an empty bar', (
    tester,
  ) async {
    await addBook('book-1', title: 'Romeo and Juliet', author: 'Shakespeare');

    await pump(tester);

    expect(find.text('Romeo and Juliet'), findsOneWidget);
    expect(find.text('Shakespeare'), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets('a book with a hint shows a percentage and a bar', (
    tester,
  ) async {
    await addBook('book-1', title: 'Romeo and Juliet', wordCount: 1000);
    await readTo('book-1', 370);

    await pump(tester);

    // tokenIndex 370 is the 371st word read out of 1000, per BookSummary's
    // own (index + 1) / wordCount — the same correction the reader screen's
    // progress bar already applied.
    expect(find.text('37%'), findsOneWidget);

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.371, 0.0001));

    await _disposeTree(tester);
  });

  testWidgets('a position from a client with no hint reads as in progress', (
    tester,
  ) async {
    await addBook('book-1', title: 'Romeo and Juliet');

    // What ADR 0013 calls a position without a count: the reader has been
    // here, and how far in is not recorded.
    await repository.savePosition(
      bookId: 'book-1',
      locator: Locator(blockId: 'block-1', charOffset: 0, parserVersion: 1),
      hlc: '0000000000001-00000-test',
    );

    await pump(tester);

    expect(find.text('In progress'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets('a book row is one node to a screen reader', (tester) async {
    await addBook('book-1', title: 'Romeo and Juliet', author: 'Shakespeare');
    await readTo('book-1', 370);

    final semantics = tester.ensureSemantics();

    await pump(tester);

    // Four stops to learn one book is three too many. The cover, title,
    // author, percentage and time left merge into a single button.
    //
    // The figure itself is matched loosely rather than pinned. It comes from
    // the default profile's pacing, so spelling it out here would make this
    // test fail the day a preset is retuned, which is not what it is about.
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Romeo and Juliet, Shakespeare, 37 percent read, .+ left$'),
      ),
      findsOneWidget,
    );

    semantics.dispose();
    await _disposeTree(tester);
  });

  group('sort', () {
    testWidgets('the field control reorders the shelf', (tester) async {
      await addBook('book-1', title: 'Zeno', wordCount: 1000);
      await addBook('book-2', title: 'Alpha', wordCount: 1000);
      await readTo('book-1', 900);

      await pump(tester, width: 360);

      // The order books arrived in is not asserted here. Drift stores
      // DateTime as whole seconds, so two imports inside one test share a
      // timestamp and the tie is broken by a sort that is not stable.
      await tester.tap(find.text(LibrarySort.recentlyAdded.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(LibrarySort.title.label).last);
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Alpha')).dy,
        lessThan(tester.getTopLeft(find.text('Zeno')).dy),
      );

      // The button now shows the label of the sort just chosen.
      await tester.tap(find.text(LibrarySort.title.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(LibrarySort.progress.label));
      await tester.pumpAndSettle();

      // Ninety percent read against a book never opened, whose progress is
      // unknown rather than zero and therefore sorts last.
      expect(
        tester.getTopLeft(find.text('Zeno')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha')).dy),
      );

      await _disposeTree(tester);
    });

    testWidgets('the direction control swaps the ends', (tester) async {
      await addBook('book-1', title: 'Zeno');
      await addBook('book-2', title: 'Alpha');

      await pump(tester, width: 360);

      await tester.tap(find.text(LibrarySort.recentlyAdded.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(LibrarySort.title.label).last);
      await tester.pumpAndSettle();

      // The end label is in the reader's terms for the field they picked,
      // rather than the word "ascending", which means the first letter here
      // and the newest book one option up.
      expect(find.text('A to Z'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Alpha')).dy,
        lessThan(tester.getTopLeft(find.text('Zeno')).dy),
      );

      await tester.tap(find.text('A to Z'));
      await tester.pumpAndSettle();

      expect(find.text('Z to A'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Zeno')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha')).dy),
      );

      await _disposeTree(tester);
    });

    testWidgets('a book nobody has opened stays last when progress flips', (
      tester,
    ) async {
      await addBook('book-1', title: 'Zeno', wordCount: 1000);
      await addBook('book-2', title: 'Alpha', wordCount: 1000);
      await readTo('book-1', 900);

      await pump(tester, width: 360);

      await tester.tap(find.text(LibrarySort.recentlyAdded.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(LibrarySort.progress.label).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Most read first'));
      await tester.pumpAndSettle();

      // Least read first, and Alpha is still underneath. Its progress is
      // unknown rather than zero, so it belongs to neither end: ADR 0013
      // draws that distinction and this is where a reader would see it
      // broken.
      expect(find.text('Least read first'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Zeno')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha')).dy),
      );

      await _disposeTree(tester);
    });

    testWidgets('changing the field starts from that field near end', (
      tester,
    ) async {
      await addBook('book-1', title: 'Zeno');

      await pump(tester, width: 360);

      await tester.tap(find.text('Newest first'));
      await tester.pumpAndSettle();
      expect(find.text('Oldest first'), findsOneWidget);

      await tester.tap(find.text(LibrarySort.recentlyAdded.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(LibrarySort.title.label).last);
      await tester.pumpAndSettle();

      // Not "Z to A". Reversing a date and reversing an alphabet are not the
      // same request, and carrying the flip across would hand the reader an
      // end they never asked for.
      expect(find.text('A to Z'), findsOneWidget);

      await _disposeTree(tester);
    });
  });

  group('adding something to read', () {
    testWidgets('the button offers a file and a paste', (tester) async {
      await addBook('book-1', title: 'Romeo and Juliet');

      await pump(tester);

      // Neither is on the shelf itself. The screen has one accent control
      // and it opens this.
      expect(find.byKey(addMenuEpubKey), findsNothing);
      expect(find.byKey(addMenuPasteKey), findsNothing);

      await tester.tap(find.byKey(libraryAddButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(addMenuEpubKey), findsOneWidget);
      expect(find.byKey(addMenuPasteKey), findsOneWidget);

      await _disposeTree(tester);
    });

    testWidgets('paste opens the paste reader', (tester) async {
      await addBook('book-1', title: 'Romeo and Juliet');

      await pump(tester);

      await tester.tap(find.byKey(libraryAddButtonKey));
      await tester.pumpAndSettle();
      // Free books now sits above it in the menu, pushing this option below
      // the dialog's own viewport at this window size.
      await tester.ensureVisible(find.byKey(addMenuPasteKey));
      await tester.tap(find.byKey(addMenuPasteKey));
      await tester.pumpAndSettle();

      // The regression this covers is not the navigation. Paste was
      // unreachable once the library had a book in it, because the only
      // control that offered it lived on the empty state.
      expect(find.byType(PasteReaderScreen), findsOneWidget);

      await _disposeTree(tester);
    });

    testWidgets('the empty library opens the same menu', (tester) async {
      await pump(tester);

      expect(find.text('Nothing here yet'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Add something to read'),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(addMenuEpubKey), findsOneWidget);
      expect(find.byKey(addMenuPasteKey), findsOneWidget);

      await _disposeTree(tester);
    });
  });

  testWidgets('a narrow window lays books out one per row', (tester) async {
    await addBook('book-1', title: 'Romeo and Juliet');

    await pump(tester, width: 360);

    // Below two columns the tile turns on its side rather than becoming one
    // giant card per screen.
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(BookCoverImage), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('the shelf survives doubled text without clipping', (
    tester,
  ) async {
    await addBook('book-1', title: 'Romeo and Juliet', author: 'Shakespeare');
    await addBook('book-2', title: 'Hamlet', author: 'Shakespeare');

    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pump(tester);

    // The tile height is computed from the scaled text block rather than
    // from a fixed aspect ratio, so nothing here should overflow. The sort
    // row is in this too: it wraps rather than clipping the label that says
    // which order the shelf is in.
    expect(tester.takeException(), isNull);
    expect(find.text('Hamlet'), findsOneWidget);
    expect(find.text('Newest first'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('removing a book is behind the menu', (tester) async {
    await addBook('book-1', title: 'Romeo and Juliet');

    await pump(tester);

    // A destructive action on a shelf should take two taps, not one.
    expect(find.text('Remove'), findsNothing);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing here yet'), findsOneWidget);

    await _disposeTree(tester);
  });
}
