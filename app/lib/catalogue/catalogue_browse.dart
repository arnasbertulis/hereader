import 'dart:async';

import '../net/http_transport.dart';
import 'catalogue_client.dart';

/// The four-way reason a Browse's results aren't what the reader expects.
/// Domain glossary: *Browse problem*. Worded distinctly on purpose —
/// [nothingMatched] and [catalogueEmpty] read as different facts to a reader,
/// not one generic "nothing here".
enum BrowseProblem {
  /// A search, a Category or a Language narrowed the Catalogue to nothing.
  nothingMatched,

  /// The Catalogue is ready but holds no Entry at all, with nothing
  /// narrowing it.
  catalogueEmpty,

  /// The device could not reach the server.
  noConnection,

  /// The server answered, but the Catalogue itself is not ready — ingestion
  /// can be mid-run or have never completed.
  catalogueUnavailable,
}

/// What [CatalogueBrowse] has to show at any moment.
sealed class BrowseState {
  const BrowseState();
}

/// The first page of a Browse is in flight, with nothing to show yet.
final class BrowseLoading extends BrowseState {
  const BrowseLoading();
}

/// The first page failed. Distinct from [BrowseReady.loadMoreProblem] — a
/// failed first load has no entries to keep on screen, so it replaces the
/// whole state rather than annotating one.
final class BrowseFailed extends BrowseState {
  final BrowseProblem problem;

  const BrowseFailed(this.problem);
}

/// At least one page has loaded. [loadMoreProblem] is set only by a failed
/// *further* page — a first-load failure is [BrowseFailed] instead, so no
/// single field here is ever asked to mean both.
final class BrowseReady extends BrowseState {
  final List<CatalogueEntry> entries;
  final bool hasMore;
  final bool loadingMore;
  final BrowseProblem? loadMoreProblem;

  const BrowseReady({
    required this.entries,
    required this.hasMore,
    this.loadingMore = false,
    this.loadMoreProblem,
  });

  /// Enter the loading-more phase, clearing any earlier load-more problem
  /// so a retry does not still show the failure it is retrying.
  BrowseReady loadingNextPage() =>
      BrowseReady(entries: entries, hasMore: hasMore, loadingMore: true);

  /// Append a resolved page.
  BrowseReady withPage(List<CatalogueEntry> page, {required bool hasMore}) =>
      BrowseReady(entries: [...entries, ...page], hasMore: hasMore);

  /// A further page failed. The pages already on screen stay exactly as
  /// they were.
  BrowseReady withLoadMoreProblem(BrowseProblem problem) =>
      BrowseReady(entries: entries, hasMore: hasMore, loadMoreProblem: problem);
}

/// Marks a [CatalogueBrowse.filtersChanged] argument as not passed, so a
/// caller can still set [CatalogueDirection] explicitly to `null` — which
/// means "this sort's own default direction", not "leave direction alone".
class _Unset {
  const _Unset();
}

const _unset = _Unset();

/// Owns one query-and-filters session against the Catalogue — the query,
/// Category, Language, sort, direction and pagination position that used to
/// be spread across `FreeBooksScreen`'s own mutable state. Performs no I/O
/// until [start] is called.
///
/// A superseded response can never overwrite a newer request's results: each
/// reset captures a generation, and a response is applied only if that
/// generation is still current when it comes back — the same technique
/// `SyncEngine` uses for its own overlapping-call guard.
///
/// Whether a failure is a first-load or a load-more failure is read off
/// [_current] in exactly one place, [_classifyProblem] — not re-decided at
/// every catch clause, which is how #211 let the two come apart.
class CatalogueBrowse {
  final CatalogueClient client;
  final Duration debounce;

  CatalogueBrowse({
    required this.client,
    this.debounce = const Duration(milliseconds: 400),
  });

  final _controller = StreamController<BrowseState>.broadcast();

  Stream<BrowseState> get state => _controller.stream;

  BrowseState _current = const BrowseLoading();
  Timer? _debounceTimer;
  int _generation = 0;

  String _query = '';
  String _category = '';
  String _language = '';
  CatalogueSort _sort = CatalogueSort.popularity;
  CatalogueDirection? _direction;
  int _page = 0;

  /// Kicks off the first load. Call once; nothing before this reaches the
  /// network.
  void start() => _load(reset: true);

  /// A keystroke in the search field. Debounced so a reader typing a whole
  /// word fires one request, not one per letter.
  void queryChanged(String text) {
    _query = text;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => _load(reset: true));
  }

  /// Category, Language, sort and/or direction changed. Resets immediately,
  /// with no debounce — unlike a keystroke, a menu choice is already a
  /// deliberate, discrete action.
  ///
  /// Only the arguments passed are changed; the rest keep their current
  /// value. [direction] is the one field where `null` is itself a value
  /// (the sort's own default direction), so it defaults to [_unset] rather
  /// than `null` to tell "not passed" apart from "set to null".
  void filtersChanged({
    String? category,
    String? language,
    CatalogueSort? sort,
    Object? direction = _unset,
  }) {
    if (category != null) _category = category;
    if (language != null) _language = language;
    if (sort != null) _sort = sort;
    if (!identical(direction, _unset)) {
      _direction = direction as CatalogueDirection?;
    }
    // A filter can land while a query's debounce is still pending; without
    // this the stale timer fires its own reset later, behind the reader's
    // back.
    _debounceTimer?.cancel();
    _load(reset: true);
  }

  /// Asks for the next page. A no-op while a load is already in flight,
  /// once there is no further page, or while a load-more error is already
  /// showing — retrying that is [filtersChanged] or another [loadMore] call
  /// after the reader acts, not an automatic repeat.
  void loadMore() {
    final current = _current;
    if (current is! BrowseReady) return;
    if (current.loadingMore ||
        !current.hasMore ||
        current.loadMoreProblem != null) {
      return;
    }
    _load(reset: false);
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      // Bumped before the request starts, so a response from a request
      // this reset itself supersedes (an older search still in flight) is
      // recognised as stale by the same check below.
      _generation += 1;
      _page = 0;
      _emit(const BrowseLoading());
    } else {
      final current = _current;
      if (current is! BrowseReady) return;
      _emit(current.loadingNextPage());
    }

    final generation = _generation;
    final query = _query.trim();
    final filtered =
        query.isNotEmpty || _category.isNotEmpty || _language.isNotEmpty;

    try {
      final result = await client.search(
        q: query,
        category: _category,
        language: _language,
        page: _page,
        sort: _sort,
        direction: _direction,
      );
      if (_stale(generation)) return;
      _page += 1;
      _applyResult(result, filtered: filtered);
    } on NetworkException {
      if (_stale(generation)) return;
      _emit(_classifyProblem(BrowseProblem.noConnection));
    } on ApiException {
      if (_stale(generation)) return;
      _emit(_classifyProblem(BrowseProblem.catalogueUnavailable));
    }
  }

  void _applyResult(CatalogueSearchResult result, {required bool filtered}) {
    if (!result.catalogueReady) {
      _emit(_classifyProblem(BrowseProblem.catalogueUnavailable));
      return;
    }

    final current = _current;
    final next = current is BrowseReady
        ? current.withPage(result.results, hasMore: result.hasMore)
        : BrowseReady(entries: result.results, hasMore: result.hasMore);

    if (next.entries.isEmpty) {
      _emit(
        _classifyProblem(
          filtered
              ? BrowseProblem.nothingMatched
              : BrowseProblem.catalogueEmpty,
        ),
      );
      return;
    }

    _emit(next);
  }

  /// The one place that decides whether a failure lands as [BrowseFailed]
  /// (nothing on screen yet) or as a [BrowseReady.loadMoreProblem] (pages
  /// already on screen, left in place) — read off [_current] rather than a
  /// flag threaded through each catch clause.
  BrowseState _classifyProblem(BrowseProblem problem) {
    final current = _current;
    return current is BrowseReady
        ? current.withLoadMoreProblem(problem)
        : BrowseFailed(problem);
  }

  bool _stale(int generation) =>
      generation != _generation || _controller.isClosed;

  void _emit(BrowseState next) {
    _current = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  /// Cancels a pending debounced search and closes [state]. No further
  /// state is emitted afterwards.
  void dispose() {
    _debounceTimer?.cancel();
    _controller.close();
  }
}
