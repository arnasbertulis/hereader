import 'dart:typed_data';

import 'package:app/catalogue/catalogue_client.dart';
import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/free_books_screen.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/sync/api_client.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'fakes.dart';
import 'test_database.dart';

LibraryBook _bookFor(String id, String title) => LibraryBook(
  id: id,
  title: title,
  text: TokenizedText.from(const [
    (id: 'one', text: 'First line.'),
  ], parserVersion: 1),
);

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

  setUp(() {
    db = AppDatabase(testExecutor());
    repository = LibraryRepository(db);
    auth = AuthStore();
    api = ApiClient(baseUrl: Uri.parse('http://localhost'), auth: auth);
    sync = SyncEngine(
      repository: repository,
      api: api,
      auth: auth,
      database: db,
    );
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
    BookImporter bookImporter = const BookImporter(),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: FreeBooksScreen(
          client: catalogue,
          repository: repository,
          sync: sync,
          bookImporter: bookImporter,
        ),
      ),
    );
  }

  CatalogueEntryStub entryStub({
    int gutenbergId = 76,
    String title = 'Adventures of Huckleberry Finn',
    String authors = 'Mark Twain',
  }) => CatalogueEntryStub(
    gutenbergId: gutenbergId,
    title: title,
    authors: authors,
  );

  testWidgets('opening with nothing typed asks for the most downloaded '
      'books', (tester) async {
    final entry = entryStub();
    catalogue.searchResponses.add(
      CatalogueSearchResult(
        catalogueReady: true,
        results: [entry.toEntry()],
        page: 0,
        hasMore: false,
      ),
    );

    await pump(tester);
    await tester.pumpAndSettle();

    expect(catalogue.searches.single.q, '');
    expect(catalogue.searches.single.sort, CatalogueSort.popularity);
    expect(find.text('Adventures of Huckleberry Finn'), findsOneWidget);
    expect(find.text('Mark Twain'), findsOneWidget);

    await _disposeTree(tester);
  });

  // Whether a keystroke waits before it becomes a search, and how long, is
  // CatalogueBrowse's own debounce and is asserted tick by tick in
  // catalogue_browse_test.dart. What is this screen's is only that the search
  // field's text reaches queryChanged at all, and that the page it comes back
  // with is what gets painted.
  testWidgets('typing in the search field searches for what was typed', (
    tester,
  ) async {
    catalogue.searchResponses.add(
      const CatalogueSearchResult(
        catalogueReady: true,
        results: [],
        page: 0,
        hasMore: false,
      ),
    );

    await pump(tester);
    await tester.pumpAndSettle();
    expect(catalogue.searches, hasLength(1));

    final entry = entryStub(
      gutenbergId: 84,
      title: 'Frankenstein',
      authors: 'Mary Shelley',
    );
    catalogue.searchResponses.add(
      CatalogueSearchResult(
        catalogueReady: true,
        results: [entry.toEntry()],
        page: 0,
        hasMore: false,
      ),
    );

    await tester.enterText(find.byKey(freeBooksSearchFieldKey), 'frank');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(catalogue.searches, hasLength(2));
    expect(catalogue.searches.last.q, 'frank');
    expect(find.text('Frankenstein'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('disposing the screen disposes the Browse with it', (
    tester,
  ) async {
    catalogue.searchResponses.add(
      const CatalogueSearchResult(
        catalogueReady: true,
        results: [],
        page: 0,
        hasMore: false,
      ),
    );

    await pump(tester);
    await tester.pumpAndSettle();
    expect(catalogue.searches, hasLength(1));

    // A keystroke leaves a debounce timer pending inside the Browse. Tearing
    // the tree down has to cancel it: an uncancelled one fires its search
    // after the screen is gone, and flutter_test reports the timer itself as
    // leaked at teardown.
    await tester.enterText(find.byKey(freeBooksSearchFieldKey), 'never fired');
    await _disposeTree(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(catalogue.searches, hasLength(1));
  });

  testWidgets('an empty catalogue with no filters active says so '
      'distinctly', (tester) async {
    catalogue.searchResponses.add(
      const CatalogueSearchResult(
        catalogueReady: true,
        results: [],
        page: 0,
        hasMore: false,
      ),
    );

    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(freeBooksMessageKey), findsOneWidget);
    expect(find.text('The catalogue has no books yet.'), findsOneWidget);
    // Nothing to retry into a different result: the reader would type a
    // different search, not press a button.
    expect(find.byKey(freeBooksRetryButtonKey), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets('zero matches under an active filter reads differently, and '
      'leaves the controls on screen', (tester) async {
    final entry = entryStub();
    catalogue.searchResponses.add(
      CatalogueSearchResult(
        catalogueReady: true,
        results: [entry.toEntry()],
        page: 0,
        hasMore: false,
      ),
    );

    await pump(tester);
    await tester.pumpAndSettle();

    catalogue.searchResponses.add(
      const CatalogueSearchResult(
        catalogueReady: true,
        results: [],
        page: 0,
        hasMore: false,
      ),
    );

    await tester.enterText(find.byKey(freeBooksSearchFieldKey), 'zzz');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(
      find.text('Nothing matched your search or filters.'),
      findsOneWidget,
    );
    // The search field and the filter menus stay mounted rather than the
    // problem view replacing the whole screen.
    expect(find.byKey(freeBooksSearchFieldKey), findsOneWidget);
    expect(find.text('All categories'), findsOneWidget);
    expect(find.byKey(freeBooksRetryButtonKey), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets('choosing a Category filters the search and combines with '
      'typed text', (tester) async {
    catalogue.categoryResponse = const [
      CategoryCount(category: 'Fiction', count: 12),
      CategoryCount(category: 'Poetry', count: 3),
    ];
    catalogue.searchResponses.add(
      const CatalogueSearchResult(
        catalogueReady: true,
        results: [],
        page: 0,
        hasMore: false,
      ),
    );

    await pump(tester);
    await tester.pumpAndSettle();
    expect(catalogue.searches.single.category, '');

    catalogue.searchResponses.add(
      const CatalogueSearchResult(
        catalogueReady: true,
        results: [],
        page: 0,
        hasMore: false,
      ),
    );

    await tester.tap(find.text('All categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fiction (12)').last);
    await tester.pumpAndSettle();

    expect(catalogue.searches.last.category, 'Fiction');
    expect(find.text('Fiction'), findsOneWidget);

    catalogue.searchResponses.add(
      const CatalogueSearchResult(
        catalogueReady: true,
        results: [],
        page: 0,
        hasMore: false,
      ),
    );
    await tester.enterText(find.byKey(freeBooksSearchFieldKey), 'twain');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(catalogue.searches.last.category, 'Fiction');
    expect(catalogue.searches.last.q, 'twain');

    await _disposeTree(tester);
  });

  testWidgets('choosing a Language filters the search', (tester) async {
    catalogue.languageResponse = const [
      LanguageCount(language: 'en', count: 40),
      LanguageCount(language: 'lt', count: 2),
    ];
    catalogue.searchResponses.add(
      const CatalogueSearchResult(
        catalogueReady: true,
        results: [],
        page: 0,
        hasMore: false,
      ),
    );

    await pump(tester);
    await tester.pumpAndSettle();
    expect(catalogue.searches.single.language, '');

    catalogue.searchResponses.add(
      const CatalogueSearchResult(
        catalogueReady: true,
        results: [],
        page: 0,
        hasMore: false,
      ),
    );

    await tester.tap(find.text('All languages'));
    await tester.pumpAndSettle();
    expect(find.text('English (40)'), findsOneWidget);
    await tester.tap(find.text('Lithuanian (2)').last);
    await tester.pumpAndSettle();

    expect(catalogue.searches.last.language, 'lt');
    expect(find.text('Lithuanian'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('choosing a sort order changes what is requested', (
    tester,
  ) async {
    catalogue.searchResponses.add(
      const CatalogueSearchResult(
        catalogueReady: true,
        results: [],
        page: 0,
        hasMore: false,
      ),
    );

    await pump(tester);
    await tester.pumpAndSettle();
    expect(catalogue.searches.single.sort, CatalogueSort.popularity);

    catalogue.searchResponses.add(
      const CatalogueSearchResult(
        catalogueReady: true,
        results: [],
        page: 0,
        hasMore: false,
      ),
    );

    await tester.tap(find.text('Most popular'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title').last);
    await tester.pumpAndSettle();

    expect(catalogue.searches.last.sort, CatalogueSort.title);

    await _disposeTree(tester);
  });

  testWidgets('reversing sort direction changes what is requested', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();
    expect(catalogue.searches.single.direction, isNull);

    await tester.tap(find.byKey(freeBooksReverseSortButtonKey));
    await tester.pumpAndSettle();

    expect(catalogue.searches.last.direction, CatalogueDirection.ascending);

    await _disposeTree(tester);
  });

  testWidgets('changing sort resets a reversed direction', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(freeBooksReverseSortButtonKey));
    await tester.pumpAndSettle();
    expect(catalogue.searches.last.direction, CatalogueDirection.ascending);

    await tester.tap(find.text('Most popular'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title').last);
    await tester.pumpAndSettle();

    expect(catalogue.searches.last.sort, CatalogueSort.title);
    expect(catalogue.searches.last.direction, isNull);

    await _disposeTree(tester);
  });

  testWidgets('no network reachable says so distinctly, with a retry', (
    tester,
  ) async {
    catalogue.nextError = const NetworkException('unreachable');

    await pump(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('No internet connection. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.byKey(freeBooksRetryButtonKey), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('an unready catalogue says so distinctly, with a retry', (
    tester,
  ) async {
    catalogue.searchResponses.add(
      const CatalogueSearchResult(
        catalogueReady: false,
        results: [],
        page: 0,
        hasMore: false,
      ),
    );

    await pump(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('The catalogue is not available right now. Try again later.'),
      findsOneWidget,
    );
    expect(find.byKey(freeBooksRetryButtonKey), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('tapping an entry not on this device imports it and stays on '
      'the screen', (tester) async {
    final entry = entryStub();
    catalogue.searchResponses.add(
      CatalogueSearchResult(
        catalogueReady: true,
        results: [entry.toEntry()],
        page: 0,
        hasMore: false,
      ),
    );
    await pump(
      tester,
      bookImporter: StubBookImporter(_bookFor(entry.bookId, entry.title)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(freeBooksTileKey(entry.gutenbergId)));
    await tester.pumpAndSettle();

    expect(catalogue.downloadRequests, [entry.gutenbergId]);
    expect(await repository.hasBook(entry.bookId), isTrue);
    expect(find.text('In your library'), findsOneWidget);
    // The reader stays on this screen, ready to add another book in the
    // same sitting, rather than being sent anywhere.
    expect(find.byType(FreeBooksScreen), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('an entry already on this device is marked as such, without '
      'being handed to the importer', (tester) async {
    // Tapping this tile is not exercised here: it opens the book through
    // BookOpener's own real BookImporter, which — like the fresh import
    // above — reparses on a real isolate via `compute()`, and this widget
    // test harness has no way to observe that isolate finish (confirmed by
    // hand: the tap alone left a run hanging past ninety seconds of real
    // time, with nothing left to fix on this screen's side of that call).
    // BookOpener is shared, pre-existing infrastructure, not new in this
    // screen, so the boundary worth testing here is the decision this
    // screen makes before reaching it.
    final entry = entryStub();
    await repository.addBook(
      _bookFor(entry.bookId, entry.title),
      Uint8List.fromList([1, 2, 3]),
    );

    catalogue.searchResponses.add(
      CatalogueSearchResult(
        catalogueReady: true,
        results: [entry.toEntry()],
        page: 0,
        hasMore: false,
      ),
    );

    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('In your library'), findsOneWidget);
    expect(catalogue.downloadRequests, isEmpty);

    await _disposeTree(tester);
  });

  testWidgets('scrolling near the bottom asks for the next page', (
    tester,
  ) async {
    final firstPage = List.generate(
      12,
      (i) => entryStub(gutenbergId: i + 1, title: 'Book $i').toEntry(),
    );
    catalogue.searchResponses.add(
      CatalogueSearchResult(
        catalogueReady: true,
        results: firstPage,
        page: 0,
        hasMore: true,
      ),
    );
    final secondEntry = entryStub(gutenbergId: 999, title: 'The Last Book');
    catalogue.searchResponses.add(
      CatalogueSearchResult(
        catalogueReady: true,
        results: [secondEntry.toEntry()],
        page: 1,
        hasMore: false,
      ),
    );

    await pump(tester);
    await tester.pumpAndSettle();
    expect(catalogue.searches, hasLength(1));

    await tester.drag(find.byKey(freeBooksGridKey), const Offset(0, -3000));
    await tester.pumpAndSettle();

    expect(catalogue.searches, hasLength(2));
    expect(catalogue.searches.last.page, 1);
    expect(find.text('The Last Book'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets(
    'a failed load-more leaves the pages already on screen and offers a '
    'retry that resumes from the same page',
    (tester) async {
      final firstPage = List.generate(
        12,
        (i) => entryStub(gutenbergId: i + 1, title: 'Book $i').toEntry(),
      );
      catalogue.searchResponses.add(
        CatalogueSearchResult(
          catalogueReady: true,
          results: firstPage,
          page: 0,
          hasMore: true,
        ),
      );

      await pump(tester);
      await tester.pumpAndSettle();

      catalogue.nextError = const NetworkException('unreachable');

      await tester.drag(find.byKey(freeBooksGridKey), const Offset(0, -3000));
      await tester.pumpAndSettle();

      // The grid from the first page is still on screen, not replaced by the
      // full-screen error — the tile nearest the scroll position, which the
      // drag put in view, is still there.
      expect(find.byKey(freeBooksGridKey), findsOneWidget);
      expect(find.text('Book 11'), findsOneWidget);
      expect(find.byKey(freeBooksMessageKey), findsNothing);
      expect(
        find.text(
          'No internet connection. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(freeBooksLoadMoreRetryButtonKey), findsOneWidget);

      final secondEntry = entryStub(gutenbergId: 999, title: 'The Last Book');
      catalogue.searchResponses.add(
        CatalogueSearchResult(
          catalogueReady: true,
          results: [secondEntry.toEntry()],
          page: 1,
          hasMore: false,
        ),
      );

      await tester.tap(find.byKey(freeBooksLoadMoreRetryButtonKey));
      await tester.pumpAndSettle();

      expect(catalogue.searches.last.page, 1);
      expect(find.text('The Last Book'), findsOneWidget);
      expect(find.byKey(freeBooksLoadMoreErrorKey), findsNothing);

      await _disposeTree(tester);
    },
  );

  testWidgets('the filters row survives doubled text without clipping', (
    tester,
  ) async {
    catalogue.categoryResponse = const [
      CategoryCount(category: 'Fiction', count: 12),
    ];
    catalogue.languageResponse = const [
      LanguageCount(language: 'en', count: 40),
    ];
    catalogue.searchResponses.add(
      const CatalogueSearchResult(
        catalogueReady: true,
        results: [],
        page: 0,
        hasMore: false,
      ),
    );

    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pump(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('All categories'), findsOneWidget);
    expect(find.text('All languages'), findsOneWidget);
    expect(find.text('Most popular'), findsOneWidget);

    await _disposeTree(tester);
  });
}

/// Builds a [CatalogueEntry] and knows the [bookId] its own import would
/// land on, so a test can seed the library at that id without repeating the
/// derivation by hand.
class CatalogueEntryStub {
  final int gutenbergId;
  final String title;
  final String authors;

  const CatalogueEntryStub({
    required this.gutenbergId,
    required this.title,
    required this.authors,
  });

  String get bookId => 'http://www.gutenberg.org/$gutenbergId';

  CatalogueEntry toEntry() => CatalogueEntry(
    gutenbergId: gutenbergId,
    title: title,
    authors: authors,
    language: 'en',
    subjects: 'Fiction',
  );
}
