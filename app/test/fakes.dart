import 'dart:async';
import 'dart:typed_data';

import 'package:app/catalogue/catalogue_client.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/sync/api_client.dart';
import 'package:app/sync/auth_store.dart';
import 'package:epub_reader/epub_reader.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

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

  /// Gates queued by [holdNextSearch], taken in call order — the first
  /// `search()` call to arrive after a gate is queued waits on it, not
  /// necessarily the call that queued it. Empty means resolve immediately,
  /// the pre-#257 default.
  final List<Completer<void>> _searchGates = [];

  List<CategoryCount> categoryResponse = const [];
  List<LanguageCount> languageResponse = const [];
  Uint8List coverBytes = Uint8List(0);
  Uint8List downloadBytes = Uint8List(0);

  /// Thrown by the next call, then cleared.
  Object? nextError;

  /// Queues a gate that the next uncommitted `search()` call will wait on.
  /// Complete the returned [Completer] to let that call proceed to its
  /// queued response. Call this once per call a test wants to hold, before
  /// making that call — queuing two gates and completing them out of order
  /// is how a test makes an earlier request resolve after a later one.
  Completer<void> holdNextSearch() {
    final gate = Completer<void>();
    _searchGates.add(gate);
    return gate;
  }

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

    // Bound to this call before the gate wait, not after: which response a
    // call gets must follow call order even when release order does not, or
    // holding an earlier call open would let a later call steal its place in
    // the response queue.
    final response = searchResponses.isNotEmpty
        ? searchResponses.removeAt(0)
        : CatalogueSearchResult(
            catalogueReady: true,
            results: const [],
            page: page,
            hasMore: false,
          );

    if (_searchGates.isNotEmpty) await _searchGates.removeAt(0).future;

    return response;
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

/// A [LibraryBook] whose [LibraryBook.text] tokenizes to exactly [wordCount]
/// tokens.
///
/// `LibraryRepository.addBook` derives its stored word count from
/// `book.text.length` rather than taking it as a separate argument, so a test
/// that wants a specific word count for a book needs a book whose text
/// actually produces that many tokens rather than an unrelated dummy value
/// passed in beside it. One block of [wordCount] space-separated placeholder
/// words tokenizes to exactly [wordCount] tokens: the default [Tokenizer]
/// splits purely on whitespace runs, and a bare word with no punctuation
/// crosses no other boundary.
LibraryBook fixtureBook({
  required String id,
  String title = 'Book',
  String? author,
  String? language,
  int wordCount = 1,
  BookSourceFormat sourceFormat = BookSourceFormat.epub,
  Uint8List? coverBytes,
}) {
  return LibraryBook(
    id: id,
    title: title,
    author: author,
    language: language,
    text: TokenizedText.from([
      (id: 'block-0', text: List.filled(wordCount, 'word').join(' ')),
    ], parserVersion: 1),
    sourceFormat: sourceFormat,
    coverBytes: coverBytes,
  );
}

/// Stands in for the real [BookParser], which parses through `compute()` —
/// a real isolate a widget test has no cheap way to wait on. Returns [book]
/// regardless of the bytes handed to it, the way [FakeCatalogueClient]
/// answers regardless of the request it was asked.
class StubBookParser extends BookParser {
  final LibraryBook book;

  const StubBookParser(this.book);

  @override
  Future<LibraryBook> import(Uint8List bytes) async => book;

  @override
  Future<LibraryBook> openNote(
    Uint8List bytes, {
    required String id,
    required String title,
  }) async => book;
}

/// Fails every parse, the way a corrupt EPUB would, with the message a
/// caller is expected to surface. Shared rather than local to one suite:
/// both the importer's own suite and the library's filter suite need a
/// failing import, and a second copy is a second message to keep in step.
class ThrowingBookParser extends BookParser {
  const ThrowingBookParser();

  @override
  Future<LibraryBook> import(Uint8List bytes) async {
    throw const EpubException('The file could not be read as an EPUB.');
  }
}
