import 'package:app/catalogue/catalogue_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CatalogueEntry', () {
    test('bookId matches the identifier a Gutenberg EPUB carries', () {
      const entry = CatalogueEntry(
        gutenbergId: 1513,
        title: 'Romeo and Juliet',
        authors: 'Shakespeare, William',
        language: 'en',
        subjects: 'Tragedies',
      );

      expect(entry.bookId, 'http://www.gutenberg.org/1513');
    });

    test('fromJson reads every field, including a null issued date', () {
      final entry = CatalogueEntry.fromJson({
        'gutenbergId': 1513,
        'title': 'Romeo and Juliet',
        'authors': 'Shakespeare, William',
        'language': 'en',
        'subjects': 'Tragedies',
        'issued': null,
      });

      expect(entry.gutenbergId, 1513);
      expect(entry.title, 'Romeo and Juliet');
      expect(entry.authors, 'Shakespeare, William');
      expect(entry.language, 'en');
      expect(entry.subjects, 'Tragedies');
      expect(entry.issued, isNull);
    });

    test('fromJson parses a present issued date', () {
      final entry = CatalogueEntry.fromJson({
        'gutenbergId': 1513,
        'title': 'Romeo and Juliet',
        'authors': 'Shakespeare, William',
        'language': 'en',
        'subjects': 'Tragedies',
        'issued': '1998-11-01',
      });

      expect(entry.issued, DateTime(1998, 11, 1));
    });
  });

  group('CategoryCount.fromJson', () {
    test('reads category and count', () {
      final count = CategoryCount.fromJson({
        'category': 'Tragedies',
        'count': 42,
      });

      expect(count.category, 'Tragedies');
      expect(count.count, 42);
    });
  });

  group('CatalogueSearchResult.fromJson', () {
    test('reads a ready page of results', () {
      final result = CatalogueSearchResult.fromJson({
        'catalogueReady': true,
        'results': [
          {
            'gutenbergId': 1513,
            'title': 'Romeo and Juliet',
            'authors': 'Shakespeare, William',
            'language': 'en',
            'subjects': 'Tragedies',
            'issued': null,
          },
        ],
        'page': 0,
        'hasMore': true,
      });

      expect(result.catalogueReady, isTrue);
      expect(result.results, hasLength(1));
      expect(result.results.single.gutenbergId, 1513);
      expect(result.page, 0);
      expect(result.hasMore, isTrue);
    });

    test('catalogueReady false is distinct from a search matching nothing', () {
      final notReady = CatalogueSearchResult.fromJson({
        'catalogueReady': false,
        'results': [],
        'page': 0,
        'hasMore': false,
      });
      final ranButEmpty = CatalogueSearchResult.fromJson({
        'catalogueReady': true,
        'results': [],
        'page': 0,
        'hasMore': false,
      });

      expect(notReady.catalogueReady, isFalse);
      expect(ranButEmpty.catalogueReady, isTrue);
      expect(notReady.results, isEmpty);
      expect(ranButEmpty.results, isEmpty);
    });
  });
}
