import 'package:app/catalogue/catalogue_browse.dart';
import 'package:app/catalogue/catalogue_client.dart';
import 'package:app/net/http_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeCatalogueClient client;

  setUp(() {
    client = FakeCatalogueClient();
  });

  CatalogueEntry entry(int id) => CatalogueEntry(
    gutenbergId: id,
    title: 'Book $id',
    authors: 'Author',
    language: 'en',
    subjects: '',
  );

  CatalogueSearchResult ready({
    List<CatalogueEntry> results = const [],
    bool hasMore = false,
  }) => CatalogueSearchResult(
    catalogueReady: true,
    results: results,
    page: 0,
    hasMore: hasMore,
  );

  List<BrowseState> track(CatalogueBrowse browse) {
    final states = <BrowseState>[];
    browse.state.listen(states.add);
    return states;
  }

  group('start', () {
    test('performs no I/O until called', () async {
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);

      await pumpEventQueue();

      expect(client.searches, isEmpty);
    });

    test('loads the first page as BrowseLoading then BrowseReady', () async {
      client.searchResponses.add(ready(results: [entry(1)], hasMore: true));
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);
      final states = track(browse);

      browse.start();
      await pumpEventQueue();

      expect(states, hasLength(2));
      expect(states[0], isA<BrowseLoading>());
      final loaded = states[1] as BrowseReady;
      expect(loaded.entries.single.gutenbergId, 1);
      expect(loaded.hasMore, isTrue);
      expect(loaded.loadingMore, isFalse);
      expect(loaded.loadMoreProblem, isNull);
    });
  });

  group('queryChanged', () {
    test(
      'debounces rapid edits into a single search after the pause',
      () async {
        client.searchResponses.add(ready());
        final browse = CatalogueBrowse(
          client: client,
          debounce: const Duration(milliseconds: 20),
        );
        addTearDown(browse.dispose);
        browse.start();
        await pumpEventQueue();
        client.searches.clear();

        browse.queryChanged('a');
        browse.queryChanged('ab');
        browse.queryChanged('abc');

        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(client.searches, isEmpty);

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(client.searches, hasLength(1));
        expect(client.searches.single.q, 'abc');
      },
    );
  });

  group('filtersChanged', () {
    test('resets immediately, with no debounce', () async {
      client.searchResponses.add(ready());
      final browse = CatalogueBrowse(
        client: client,
        debounce: const Duration(seconds: 30),
      );
      addTearDown(browse.dispose);
      browse.start();
      await pumpEventQueue();
      client.searches.clear();

      browse.filtersChanged(category: 'Fiction');
      await pumpEventQueue();

      expect(client.searches, hasLength(1));
      expect(client.searches.single.category, 'Fiction');
    });

    test(
      'cancels a pending query debounce; it never fires a second reset',
      () async {
        client.searchResponses.addAll([ready(), ready()]);
        final browse = CatalogueBrowse(
          client: client,
          debounce: const Duration(milliseconds: 20),
        );
        addTearDown(browse.dispose);
        browse.start();
        await pumpEventQueue();
        client.searches.clear();

        browse.queryChanged('a');
        browse.filtersChanged(category: 'Fiction');
        await pumpEventQueue();

        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(client.searches, hasLength(1));
        expect(client.searches.single.category, 'Fiction');
      },
    );

    test('changes only the fields passed', () async {
      client.searchResponses.addAll([ready(), ready()]);
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);
      browse.start();
      await pumpEventQueue();

      browse.filtersChanged(direction: CatalogueDirection.ascending);
      await pumpEventQueue();
      expect(client.searches.last.direction, CatalogueDirection.ascending);
      expect(client.searches.last.category, '');

      // category changes; direction is not passed, so it stays ascending.
      browse.filtersChanged(category: 'Fiction');
      await pumpEventQueue();
      expect(client.searches.last.category, 'Fiction');
      expect(client.searches.last.direction, CatalogueDirection.ascending);
    });
  });

  group('direction', () {
    test(
      'every search carries an explicit direction, from the first',
      () async {
        client.searchResponses.add(ready());
        final browse = CatalogueBrowse(client: client);
        addTearDown(browse.dispose);

        browse.start();
        await pumpEventQueue();

        expect(client.searches.single.direction, isNotNull);
      },
    );

    test('popularity resolves descending; the other three ascending', () async {
      client.searchResponses.addAll([ready(), ready(), ready(), ready()]);
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);
      browse.start();
      await pumpEventQueue();
      expect(client.searches.last.direction, CatalogueDirection.descending);

      for (final sort in [
        CatalogueSort.title,
        CatalogueSort.author,
        CatalogueSort.issued,
      ]) {
        browse.filtersChanged(sort: sort);
        await pumpEventQueue();
        expect(client.searches.last.direction, CatalogueDirection.ascending);
      }
    });

    test(
      'toggling yields the opposite of the active sort\'s default',
      () async {
        client.searchResponses.addAll([ready(), ready()]);
        final browse = CatalogueBrowse(client: client);
        addTearDown(browse.dispose);
        browse.start();
        await pumpEventQueue();

        browse.toggleDirection();
        await pumpEventQueue();

        expect(client.searches.last.direction, CatalogueDirection.ascending);
        expect(browse.reversed, isTrue);
      },
    );

    test('toggling twice returns to the default', () async {
      client.searchResponses.addAll([ready(), ready(), ready()]);
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);
      browse.start();
      await pumpEventQueue();

      browse.toggleDirection();
      await pumpEventQueue();
      browse.toggleDirection();
      await pumpEventQueue();

      expect(client.searches.last.direction, CatalogueDirection.descending);
      expect(browse.reversed, isFalse);
    });

    test(
      'changing sort resets a reversal to the new sort\'s default',
      () async {
        client.searchResponses.addAll([ready(), ready(), ready()]);
        final browse = CatalogueBrowse(client: client);
        addTearDown(browse.dispose);
        browse.start();
        await pumpEventQueue();

        browse.toggleDirection();
        await pumpEventQueue();
        expect(browse.reversed, isTrue);

        browse.filtersChanged(sort: CatalogueSort.title);
        await pumpEventQueue();

        expect(client.searches.last.direction, CatalogueDirection.ascending);
        expect(browse.reversed, isFalse);
      },
    );

    test('the reversed flag agrees with the direction actually sent', () async {
      client.searchResponses.addAll([ready(), ready()]);
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);
      browse.start();
      await pumpEventQueue();
      expect(browse.reversed, isFalse);
      expect(browse.direction, client.searches.last.direction);

      browse.toggleDirection();
      await pumpEventQueue();
      expect(browse.reversed, isTrue);
      expect(browse.direction, client.searches.last.direction);
    });
  });

  group('generation guard', () {
    test(
      'a superseded response never overwrites a newer request\'s results',
      () async {
        client.searchResponses.addAll([
          ready(results: [entry(1)]),
          ready(results: [entry(2)]),
        ]);
        final olderGate = client.holdNextSearch();
        final newerGate = client.holdNextSearch();

        final browse = CatalogueBrowse(client: client);
        addTearDown(browse.dispose);
        final states = track(browse);

        browse.start();
        await pumpEventQueue();
        browse.filtersChanged(category: 'Fiction');
        await pumpEventQueue();

        // Release the older call's gate first, out of order.
        olderGate.complete();
        await pumpEventQueue();
        newerGate.complete();
        await pumpEventQueue();

        final last = states.last as BrowseReady;
        expect(last.entries.single.gutenbergId, 2);
      },
    );
  });

  group('problem classification, first load', () {
    test('no filter and no results -> catalogueEmpty', () async {
      client.searchResponses.add(ready());
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);
      final states = track(browse);

      browse.start();
      await pumpEventQueue();

      final failed = states.last as BrowseFailed;
      expect(failed.problem, BrowseProblem.catalogueEmpty);
    });

    test('a query narrowing results to nothing -> nothingMatched', () async {
      client.searchResponses.addAll([
        ready(results: [entry(1)]),
        ready(),
      ]);
      final browse = CatalogueBrowse(
        client: client,
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(browse.dispose);
      final states = track(browse);

      browse.start();
      await pumpEventQueue();

      browse.queryChanged('nothing like this exists');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final failed = states.last as BrowseFailed;
      expect(failed.problem, BrowseProblem.nothingMatched);
    });

    test('a network failure -> noConnection', () async {
      client.nextError = const NetworkException('unreachable');
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);
      final states = track(browse);

      browse.start();
      await pumpEventQueue();

      final failed = states.last as BrowseFailed;
      expect(failed.problem, BrowseProblem.noConnection);
    });

    test('an API failure -> catalogueUnavailable', () async {
      client.nextError = const ApiException(500, 'boom');
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);
      final states = track(browse);

      browse.start();
      await pumpEventQueue();

      final failed = states.last as BrowseFailed;
      expect(failed.problem, BrowseProblem.catalogueUnavailable);
    });

    test('the catalogue not yet ready -> catalogueUnavailable', () async {
      client.searchResponses.add(
        const CatalogueSearchResult(
          catalogueReady: false,
          results: [],
          page: 0,
          hasMore: false,
        ),
      );
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);
      final states = track(browse);

      browse.start();
      await pumpEventQueue();

      final failed = states.last as BrowseFailed;
      expect(failed.problem, BrowseProblem.catalogueUnavailable);
    });
  });

  group('problem classification, load-more', () {
    test(
      'a failed further page sets loadMoreProblem, leaving entries in place',
      () async {
        client.searchResponses.add(ready(results: [entry(1)], hasMore: true));
        final browse = CatalogueBrowse(client: client);
        addTearDown(browse.dispose);
        final states = track(browse);

        browse.start();
        await pumpEventQueue();

        client.nextError = const NetworkException('unreachable');
        browse.loadMore();
        await pumpEventQueue();

        final result = states.last as BrowseReady;
        expect(result.entries.single.gutenbergId, 1);
        expect(result.loadingMore, isFalse);
        expect(result.loadMoreProblem, BrowseProblem.noConnection);
      },
    );

    test(
      'a successful further page appends and clears any earlier problem',
      () async {
        client.searchResponses.addAll([
          ready(results: [entry(1)], hasMore: true),
          ready(results: [entry(2)], hasMore: false),
        ]);
        final browse = CatalogueBrowse(client: client);
        addTearDown(browse.dispose);
        final states = track(browse);

        browse.start();
        await pumpEventQueue();
        browse.loadMore();
        await pumpEventQueue();

        final result = states.last as BrowseReady;
        expect(result.entries.map((e) => e.gutenbergId).toList(), [1, 2]);
        expect(result.hasMore, isFalse);
        expect(result.loadMoreProblem, isNull);
      },
    );
  });

  group('loadMore guards', () {
    test('is a no-op while a load is already in flight', () async {
      client.searchResponses.add(ready(results: [entry(1)], hasMore: true));
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);

      browse.start();
      await pumpEventQueue();

      final gate = client.holdNextSearch();
      client.searchResponses.add(ready(results: [entry(2)], hasMore: true));

      browse.loadMore();
      browse.loadMore();
      await pumpEventQueue();

      expect(client.searches, hasLength(2));
      gate.complete();
      await pumpEventQueue();
    });

    test('is a no-op once there is no further page', () async {
      client.searchResponses.add(ready(results: [entry(1)], hasMore: false));
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);

      browse.start();
      await pumpEventQueue();
      client.searches.clear();

      browse.loadMore();
      await pumpEventQueue();

      expect(client.searches, isEmpty);
    });

    test('carries the active filters into the further page request', () async {
      client.searchResponses.addAll([
        ready(results: [entry(1)], hasMore: true),
        ready(results: [entry(2)], hasMore: false),
      ]);
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);

      browse.filtersChanged(category: 'Fiction', language: 'fr');
      await pumpEventQueue();
      browse.loadMore();
      await pumpEventQueue();

      expect(client.searches.last.page, 1);
      expect(client.searches.last.category, 'Fiction');
      expect(client.searches.last.language, 'fr');
    });

    test('is a no-op while a load-more error is already showing', () async {
      client.searchResponses.add(ready(results: [entry(1)], hasMore: true));
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);

      browse.start();
      await pumpEventQueue();

      client.nextError = const NetworkException('unreachable');
      browse.loadMore();
      await pumpEventQueue();
      client.searches.clear();

      browse.loadMore();
      await pumpEventQueue();

      expect(client.searches, isEmpty);
    });
  });

  group('filter getters', () {
    test('start at the defaults a fresh Browse queries with', () async {
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);

      expect(browse.category, '');
      expect(browse.language, '');
      expect(browse.sort, CatalogueSort.popularity);
      expect(browse.direction, CatalogueDirection.descending);
    });

    test('report what filtersChanged last set', () async {
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);

      browse.filtersChanged(
        category: 'Fiction',
        language: 'fr',
        sort: CatalogueSort.title,
        direction: CatalogueDirection.descending,
      );
      await pumpEventQueue();

      expect(browse.category, 'Fiction');
      expect(browse.language, 'fr');
      expect(browse.sort, CatalogueSort.title);
      expect(browse.direction, CatalogueDirection.descending);
    });
  });

  group('retryLoadMore', () {
    test('re-requests the page that failed, keeping the entries', () async {
      client.searchResponses.add(ready(results: [entry(1)], hasMore: true));
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);
      final states = track(browse);

      browse.start();
      await pumpEventQueue();

      client.nextError = const NetworkException('unreachable');
      browse.loadMore();
      await pumpEventQueue();
      client.searches.clear();

      client.searchResponses.add(ready(results: [entry(2)], hasMore: false));
      browse.retryLoadMore();
      await pumpEventQueue();

      expect(client.searches.single.page, 1);
      final result = states.last as BrowseReady;
      expect(result.entries.map((e) => e.gutenbergId).toList(), [1, 2]);
      expect(result.loadMoreProblem, isNull);
    });

    test('is a no-op with no load-more problem showing', () async {
      client.searchResponses.add(ready(results: [entry(1)], hasMore: true));
      final browse = CatalogueBrowse(client: client);
      addTearDown(browse.dispose);

      browse.start();
      await pumpEventQueue();
      client.searches.clear();

      browse.retryLoadMore();
      await pumpEventQueue();

      expect(client.searches, isEmpty);
    });
  });

  group('dispose', () {
    test(
      'cancels a pending debounced search; no further state is emitted',
      () async {
        client.searchResponses.add(ready());
        final browse = CatalogueBrowse(
          client: client,
          debounce: const Duration(milliseconds: 20),
        );
        final states = track(browse);

        browse.start();
        await pumpEventQueue();
        final countBeforeDispose = states.length;

        browse.queryChanged('never fired');
        browse.dispose();

        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(client.searches, hasLength(1)); // only the start() search.
        expect(states.length, countBeforeDispose);
      },
    );
  });
}
