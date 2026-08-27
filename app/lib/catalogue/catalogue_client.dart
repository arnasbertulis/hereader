import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../net/http_transport.dart';

/// Order the Catalogue is searched in.
///
/// Matches `CatalogueDtos.Sort` on the server; `.name` is the literal query
/// value the `/catalogue/search` endpoint accepts.
enum CatalogueSort { title, author, issued, popularity }

/// Which end of [CatalogueSort] the search starts from.
///
/// Matches `CatalogueDtos.Direction` on the server; `.name` is the literal
/// query value (`ascending`/`descending`) the `/catalogue/search` endpoint
/// accepts, case-insensitively. Omitting it entirely (`null`) preserves each
/// [CatalogueSort]'s own default — descending for popularity, ascending for
/// everything else — which is why [search] takes this as nullable rather than
/// defaulting it client-side.
enum CatalogueDirection { ascending, descending }

/// One book as the Catalogue knows it — enough to list, search and offer it.
/// Mirrors `CatalogueDtos.Entry` on the server.
class CatalogueEntry {
  final int gutenbergId;
  final String title;
  final String authors;
  final String language;
  final String subjects;
  final DateTime? issued;

  const CatalogueEntry({
    required this.gutenbergId,
    required this.title,
    required this.authors,
    required this.language,
    required this.subjects,
    this.issued,
  });

  /// The id a [LibraryBook] gets once this entry is downloaded and imported.
  ///
  /// Matches the `dc:identifier` a Gutenberg EPUB carries in its own bytes
  /// (see `_idFor` in `reading/library_book.dart`), so a catalogue import and
  /// a hand-picked file of the same book collide on one row, and the same
  /// catalogue book imported on two devices shares one id and syncs its
  /// reading position with no file moving. Whether this entry is already in
  /// the Library is answered by this id and `LibraryRepository.hasBook`, with
  /// no separate lookup and no new column.
  String get bookId => 'http://www.gutenberg.org/$gutenbergId';

  factory CatalogueEntry.fromJson(Map<String, dynamic> json) => CatalogueEntry(
    gutenbergId: (json['gutenbergId'] as num).toInt(),
    title: json['title'] as String,
    authors: json['authors'] as String,
    language: json['language'] as String,
    subjects: json['subjects'] as String,
    issued: json['issued'] == null
        ? null
        : DateTime.tryParse(json['issued'] as String),
  );
}

/// One subject category and how many Catalogue Entries carry it.
/// Mirrors `CatalogueDtos.CategoryCount` on the server.
class CategoryCount {
  final String category;
  final int count;

  const CategoryCount({required this.category, required this.count});

  factory CategoryCount.fromJson(Map<String, dynamic> json) => CategoryCount(
    category: json['category'] as String,
    count: (json['count'] as num).toInt(),
  );
}

/// One language and how many Catalogue Entries carry it.
/// Mirrors `CatalogueDtos.LanguageCount` on the server.
class LanguageCount {
  final String language;
  final int count;

  const LanguageCount({required this.language, required this.count});

  factory LanguageCount.fromJson(Map<String, dynamic> json) => LanguageCount(
    language: json['language'] as String,
    count: (json['count'] as num).toInt(),
  );
}

/// A page of Catalogue search results. Mirrors `CatalogueDtos.SearchResponse`
/// on the server.
class CatalogueSearchResult {
  /// False only when ingestion has never completed. Distinct from a search
  /// that ran and matched nothing, which reports true with an empty
  /// [results] — the caller can tell "try again later" from "no such book"
  /// without guessing at an empty list's cause.
  final bool catalogueReady;

  final List<CatalogueEntry> results;
  final int page;

  /// Whether a further page exists. From an overshoot fetch server-side, the
  /// same trick sync's `PullResult.hasMore` uses — no cursor to carry.
  final bool hasMore;

  const CatalogueSearchResult({
    required this.catalogueReady,
    required this.results,
    required this.page,
    required this.hasMore,
  });

  factory CatalogueSearchResult.fromJson(Map<String, dynamic> json) =>
      CatalogueSearchResult(
        catalogueReady: json['catalogueReady'] as bool,
        results: (json['results'] as List)
            .cast<Map<String, dynamic>>()
            .map(CatalogueEntry.fromJson)
            .toList(),
        page: (json['page'] as num).toInt(),
        hasMore: json['hasMore'] as bool? ?? false,
      );
}

/// Talks to the server's Catalogue: search it, browse its categories, fetch
/// a cover, download a book's file.
///
/// Every route is `permitAll` (`CatalogueController`), so unlike [ApiClient]
/// this carries no session and refreshes no token.
///
/// Reuses [ApiException] and [NetworkException] from `net/http_transport.dart`
/// rather than a second pair of its own: "the API said no" and "the network
/// was unreachable" are the same two facts there and here, and a caller
/// already knows how to tell them apart from one.
class CatalogueClient {
  final Uri baseUrl;
  final HttpTransport _transport;

  CatalogueClient({required this.baseUrl, http.Client? httpClient})
    : _transport = HttpTransport(httpClient ?? http.Client());

  Future<CatalogueSearchResult> search({
    String q = '',
    String category = '',
    String language = '',
    int page = 0,
    int? size,
    CatalogueSort? sort,
    CatalogueDirection? direction,
  }) async {
    final body = await _getJson(
      '/catalogue/search',
      query: {
        'q': q,
        'category': category,
        'language': language,
        'page': '$page',
        if (size != null) 'size': '$size',
        if (sort != null) 'sort': sort.name,
        if (direction != null) 'direction': direction.name,
      },
    );

    return CatalogueSearchResult.fromJson(body);
  }

  Future<List<CategoryCount>> categories() async {
    final body = await _getJson('/catalogue/categories', expectList: true);

    return (body['items'] as List)
        .cast<Map<String, dynamic>>()
        .map(CategoryCount.fromJson)
        .toList();
  }

  Future<List<LanguageCount>> languages() async {
    final body = await _getJson('/catalogue/languages', expectList: true);

    return (body['items'] as List)
        .cast<Map<String, dynamic>>()
        .map(LanguageCount.fromJson)
        .toList();
  }

  Future<Uint8List> cover(int gutenbergId) =>
      _getBytes('/catalogue/cover/$gutenbergId');

  Future<Uint8List> download(int gutenbergId) =>
      _getBytes('/catalogue/download/$gutenbergId');

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? query,
    bool expectList = false,
  }) async {
    final response = await _get(path, query: query);
    return _transport.readJson(response, expectList: expectList);
  }

  Future<Uint8List> _getBytes(String path) async {
    final response = await _get(path);
    return response.bodyBytes;
  }

  Future<http.Response> _get(String path, {Map<String, String>? query}) async {
    final uri = baseUrl.replace(
      path: '${baseUrl.path}$path',
      queryParameters: query,
    );

    final response = await _transport.send('GET', uri);
    return _transport.checkStatus(response);
  }

  void dispose() => _transport.dispose();
}
