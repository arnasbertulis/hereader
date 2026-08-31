// Tests the shared test fake itself, not production code — #257 gave
// FakeCatalogueClient controllable request timing so a test elsewhere can
// exercise the generation-guard race in the upcoming CatalogueBrowse module
// (#217). Regression coverage belongs here, next to the fake, rather than in
// a module that does not exist yet.
import 'package:app/catalogue/catalogue_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('FakeCatalogueClient.search', () {
    test('resolves immediately with no held gate, as before #257', () async {
      final fake = FakeCatalogueClient();
      fake.searchResponses.add(
        const CatalogueSearchResult(
          catalogueReady: true,
          results: [],
          page: 0,
          hasMore: false,
        ),
      );

      final result = await fake.search(q: 'anything');

      expect(result.page, 0);
      expect(fake.searches, hasLength(1));
    });

    test('two held calls resolve in release order, not call order', () async {
      final fake = FakeCatalogueClient();
      final firstResult = CatalogueSearchResult(
        catalogueReady: true,
        results: const [],
        page: 1,
        hasMore: false,
      );
      final secondResult = CatalogueSearchResult(
        catalogueReady: true,
        results: const [],
        page: 2,
        hasMore: false,
      );
      fake.searchResponses.addAll([firstResult, secondResult]);

      final firstGate = fake.holdNextSearch();
      final secondGate = fake.holdNextSearch();

      final released = <int>[];
      final firstFuture = fake
          .search(q: 'first')
          .then((r) => released.add(r.page));
      final secondFuture = fake
          .search(q: 'second')
          .then((r) => released.add(r.page));

      // Both calls are in flight and held; neither has resolved yet.
      expect(released, isEmpty);

      // Release the second call's gate first: its result must land first,
      // even though the first call was made first.
      secondGate.complete();
      await secondFuture;
      expect(released, [2]);

      firstGate.complete();
      await firstFuture;
      expect(released, [2, 1]);
    });
  });
}
