import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/book_cover.dart';
import 'package:app/reading/library_screen.dart';
import 'package:app/sync/api_client.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

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

  Future<void> addBook(
    String id, {
    required String title,
    String? author,
    int wordCount = 1000,
    Uint8List? cover,
  }) => repository.addBook(
    id: id,
    title: title,
    author: author,
    bytes: Uint8List.fromList([1, 2, 3]),
    wordCount: wordCount,
    coverBytes: cover,
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
        home: LibraryScreen(repository: repository, sync: sync, api: api, issueStamp: _stamp),
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

    expect(find.text('37%'), findsOneWidget);

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.37, 0.001));

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
    // author and percentage merge into a single button.
    expect(
      find.bySemanticsLabel('Romeo and Juliet, Shakespeare, 37 percent read'),
      findsOneWidget,
    );

    semantics.dispose();
    await _disposeTree(tester);
  });

  testWidgets('the sort control reorders the shelf', (tester) async {
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
    // from a fixed aspect ratio, so nothing here should overflow.
    expect(tester.takeException(), isNull);
    expect(find.text('Hamlet'), findsOneWidget);

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

    expect(find.text('No books yet'), findsOneWidget);

    await _disposeTree(tester);
  });
}
