import 'dart:typed_data';

import 'package:app/catalogue/catalogue_client.dart';
import 'package:app/sync/api_client.dart';
import 'package:app/sync/auth_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// In-memory secure storage.
///
/// The real one needs platform channels, which a test does not have.
///
/// Extends rather than implements: the interface has sixteen members and
/// this needs three. A `noSuchMethod` fallback would cover the rest, but it
/// turns a signature mismatch into a silent no-op rather than a compile
/// error, which is how an earlier version of this fake quietly stored
/// nothing at all.
class FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    values.remove(key);
  }
}

/// A service that records what it was asked and answers what it was told to.
///
/// Standing in for the real one rather than running Spring in a test: the
/// service has its own suite, and what matters here is what the client does
/// with each kind of answer.
class FakeApi implements ApiClient {
  @override
  final AuthStore auth;

  @override
  final Uri baseUrl = Uri.parse('http://localhost');

  /// Every batch pushed, in order, so a test can assert what was sent and
  /// what was not.
  final List<List<Map<String, dynamic>>> pushed = [];

  final List<int> pulledSince = [];

  /// Queued responses, taken in order. A test that pushes twice can make the
  /// second answer differ from the first.
  final List<PushResult> pushResponses = [];
  final List<PullResult> pullResponses = [];

  List<PositionConflict> pendingConflicts = [];

  /// Thrown by the next call, then cleared.
  Object? nextError;

  int resolvedConflicts = 0;
  int conflictFetches = 0;

  FakeApi({required this.auth});

  @override
  Future<PushResult> push({
    required String deviceId,
    required List<Map<String, dynamic>> events,
  }) async {
    _maybeThrow();
    pushed.add(events);

    if (pushResponses.isNotEmpty) return pushResponses.removeAt(0);

    return PushResult(
      lastSeq: pushed.length,
      accepted: events.length,
      duplicates: const [],
      conflicts: const [],
    );
  }

  @override
  Future<PullResult> pull({required int since, int limit = 200}) async {
    _maybeThrow();
    pulledSince.add(since);

    if (pullResponses.isNotEmpty) return pullResponses.removeAt(0);

    return PullResult(events: const [], lastSeq: since, hasMore: false);
  }

  @override
  Future<List<PositionConflict>> conflicts() async {
    _maybeThrow();
    conflictFetches++;
    return pendingConflicts;
  }

  @override
  Future<void> resolveConflict({
    required int conflictId,
    required Map<String, dynamic> chosen,
    required String hlc,
    required String deviceId,
  }) async {
    _maybeThrow();
    resolvedConflicts++;
    pendingConflicts = pendingConflicts
        .where((c) => c.id != conflictId)
        .toList();
  }

  // Authentication is not what these tests are about: a session is put in
  // the store directly. Reaching these would mean the engine did something
  // it has no business doing.

  @override
  Future<Session> register(String email, String password) =>
      throw UnimplementedError('The sync engine does not register.');

  @override
  Future<Session> logIn(String email, String password) =>
      throw UnimplementedError('The sync engine does not sign in.');

  @override
  Future<void> logOut() =>
      throw UnimplementedError('The sync engine does not sign out.');

  @override
  void dispose() {}

  void _maybeThrow() {
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }
}

/// A Catalogue that records what it was asked and answers what it was told
/// to. Standing in for `CatalogueClient` the same way [FakeApi] stands in
/// for `ApiClient`: no test reaches the network.
class FakeCatalogueClient implements CatalogueClient {
  @override
  final Uri baseUrl = Uri.parse('http://localhost');

  /// Every search made, in order.
  final List<
    ({
      String q,
      String category,
      String language,
      int page,
      int? size,
      CatalogueSort? sort,
      CatalogueDirection? direction,
    })
  >
  searches = [];

  final List<int> coverRequests = [];
  final List<int> downloadRequests = [];

  /// Queued responses, taken in order. Empty defaults to a ready, empty page.
  final List<CatalogueSearchResult> searchResponses = [];

  List<CategoryCount> categoryResponse = const [];
  List<LanguageCount> languageResponse = const [];
  Uint8List coverBytes = Uint8List(0);
  Uint8List downloadBytes = Uint8List(0);

  /// Thrown by the next call, then cleared.
  Object? nextError;

  @override
  Future<CatalogueSearchResult> search({
    String q = '',
    String category = '',
    String language = '',
    int page = 0,
    int? size,
    CatalogueSort? sort,
    CatalogueDirection? direction,
  }) async {
    _maybeThrow();
    searches.add((
      q: q,
      category: category,
      language: language,
      page: page,
      size: size,
      sort: sort,
      direction: direction,
    ));

    if (searchResponses.isNotEmpty) return searchResponses.removeAt(0);

    return CatalogueSearchResult(
      catalogueReady: true,
      results: const [],
      page: page,
      hasMore: false,
    );
  }

  @override
  Future<List<CategoryCount>> categories() async {
    _maybeThrow();
    return categoryResponse;
  }

  @override
  Future<List<LanguageCount>> languages() async {
    _maybeThrow();
    return languageResponse;
  }

  @override
  Future<Uint8List> cover(int gutenbergId) async {
    _maybeThrow();
    coverRequests.add(gutenbergId);
    return coverBytes;
  }

  @override
  Future<Uint8List> download(int gutenbergId) async {
    _maybeThrow();
    downloadRequests.add(gutenbergId);
    return downloadBytes;
  }

  @override
  void dispose() {}

  void _maybeThrow() {
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }
}
