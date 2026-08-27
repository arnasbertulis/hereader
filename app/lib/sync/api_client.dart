import 'dart:async';

import 'package:http/http.dart' as http;

import '../net/http_transport.dart';
import 'auth_store.dart';

export '../net/http_transport.dart' show ApiException, NetworkException;

/// Calls the sync service.
///
/// Refreshes an expired access token transparently, so nothing above this
/// has to think about token lifetimes. A caller sees a 401 only when the
/// refresh token has expired too, which means the reader must sign in again.
class ApiClient {
  final Uri baseUrl;
  final AuthStore auth;
  final HttpTransport _transport;

  /// Guards against a burst of parallel requests each triggering their own
  /// refresh. The first one refreshes; the rest wait for it.
  Future<void>? _refreshing;

  ApiClient({
    required this.baseUrl,
    required this.auth,
    http.Client? httpClient,
  }) : _transport = HttpTransport(httpClient ?? http.Client());

  // -- auth ----------------------------------------------------------

  Future<Session> register(String email, String password) =>
      _authenticate('/auth/register', email, password);

  Future<Session> logIn(String email, String password) =>
      _authenticate('/auth/login', email, password);

  Future<Session> _authenticate(
    String path,
    String email,
    String password,
  ) async {
    final body = await _send(
      'POST',
      path,
      body: {'email': email, 'password': password},
      authenticated: false,
    );

    final session = Session(
      accessToken: body['accessToken'] as String,
      refreshToken: body['refreshToken'] as String,
    );

    await auth.save(session);
    return session;
  }

  /// Best-effort: signing out succeeds from the device's point of view
  /// whether or not the server call lands, so a failure here still falls
  /// through to clearing local storage.
  Future<void> logOut() async {
    try {
      await _send('POST', '/auth/logout');
    } on ApiException {
      // Rejected or already revoked. Nothing more to do server-side.
    } on NetworkException {
      // Offline. The token stays valid server-side, but the device signs
      // out locally regardless.
    }
    await auth.clear();
  }

  // -- sync ----------------------------------------------------------

  /// Pushes a batch from the outbox.
  ///
  /// Safe to call again with the same events: they carry idempotency keys,
  /// and the service reports ones it has already seen rather than applying
  /// them twice.
  Future<PushResult> push({
    required String deviceId,
    required List<Map<String, dynamic>> events,
  }) async {
    final body = await _send(
      'POST',
      '/sync/events',
      body: {'deviceId': deviceId, 'events': events},
    );

    return PushResult(
      lastSeq: (body['lastSeq'] as num).toInt(),
      accepted: (body['accepted'] as num).toInt(),
      duplicates: (body['duplicates'] as List).cast<String>(),
      conflicts: (body['conflicts'] as List)
          .cast<Map<String, dynamic>>()
          .map(PositionConflict.fromJson)
          .toList(),
    );
  }

  /// Everything after [since], oldest first.
  Future<PullResult> pull({required int since, int limit = 200}) async {
    final body = await _send(
      'GET',
      '/sync/events',
      query: {'since': '$since', 'limit': '$limit'},
    );

    return PullResult(
      events: (body['events'] as List)
          .cast<Map<String, dynamic>>()
          .map(PulledEvent.fromJson)
          .toList(),
      lastSeq: (body['lastSeq'] as num).toInt(),
      hasMore: body['hasMore'] as bool? ?? false,
    );
  }

  Future<List<PositionConflict>> conflicts() async {
    final body = await _send('GET', '/sync/conflicts', expectList: true);

    return (body['items'] as List)
        .cast<Map<String, dynamic>>()
        .map(PositionConflict.fromJson)
        .toList();
  }

  Future<void> resolveConflict({
    required int conflictId,
    required Map<String, dynamic> chosen,
    required String hlc,
    required String deviceId,
  }) async {
    await _send(
      'POST',
      '/sync/conflicts/$conflictId/resolve',
      body: {'chosen': chosen, 'hlc': hlc, 'deviceId': deviceId},
    );
  }

  // -- plumbing ------------------------------------------------------

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authenticated = true,
    bool expectList = false,
    bool isRetry = false,
  }) async {
    final uri = baseUrl.replace(
      path: '${baseUrl.path}$path',
      queryParameters: query,
    );

    final headers = <String, String>{};
    if (authenticated) {
      final token = auth.current?.accessToken;
      if (token == null) {
        throw const ApiException(401, 'Not signed in.');
      }
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await _transport.send(
      method,
      uri,
      headers: headers,
      jsonBody: body,
    );

    // An expired access token. Refresh once and retry; a second 401 means
    // the refresh token is gone too.
    if (response.statusCode == 401 && authenticated && !isRetry) {
      final refreshed = await _refreshOnce();
      if (refreshed) {
        return _send(
          method,
          path,
          body: body,
          query: query,
          authenticated: authenticated,
          expectList: expectList,
          isRetry: true,
        );
      }
    }

    return _transport.readJson(response, expectList: expectList);
  }

  /// Trades the refresh token for a new pair.
  ///
  /// Concurrent callers share one attempt: without this, ten queued requests
  /// hitting an expired token would fire ten refreshes, nine of which are
  /// wasted and any of which could race the others into storage.
  Future<bool> _refreshOnce() async {
    if (_refreshing != null) {
      await _refreshing;
      return auth.isSignedIn;
    }

    final completer = Completer<void>();
    _refreshing = completer.future;

    try {
      final token = auth.current?.refreshToken;
      if (token == null) return false;

      final body = await _send(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': token},
        authenticated: false,
      );

      await auth.save(
        Session(
          accessToken: body['accessToken'] as String,
          refreshToken: body['refreshToken'] as String,
        ),
      );

      return true;
    } on ApiException {
      // The refresh token is expired or revoked. The reader must sign in
      // again; clearing here means the app sees a signed-out state rather
      // than retrying forever with a dead credential.
      await auth.clear();
      return false;
    } on NetworkException {
      // Offline. The token may be perfectly good, so it is not cleared.
      return false;
    } finally {
      completer.complete();
      _refreshing = null;
    }
  }

  void dispose() => _transport.dispose();
}

// -- results -----------------------------------------------------------

class PushResult {
  final int lastSeq;
  final int accepted;

  /// Keys the service had already seen. Not an error: an earlier response
  /// was lost and this client retried correctly.
  final List<String> duplicates;

  final List<PositionConflict> conflicts;

  const PushResult({
    required this.lastSeq,
    required this.accepted,
    required this.duplicates,
    required this.conflicts,
  });
}

class PullResult {
  final List<PulledEvent> events;
  final int lastSeq;
  final bool hasMore;

  const PullResult({
    required this.events,
    required this.lastSeq,
    required this.hasMore,
  });
}

class PulledEvent {
  final int seq;
  final String entityType;
  final String entityId;
  final Map<String, dynamic> payload;
  final String hlc;
  final String deviceId;
  final bool deleted;

  const PulledEvent({
    required this.seq,
    required this.entityType,
    required this.entityId,
    required this.payload,
    required this.hlc,
    required this.deviceId,
    required this.deleted,
  });

  factory PulledEvent.fromJson(Map<String, dynamic> json) => PulledEvent(
    seq: (json['seq'] as num).toInt(),
    entityType: json['entityType'] as String,
    entityId: json['entityId'] as String,
    payload: (json['payload'] as Map).cast<String, dynamic>(),
    hlc: json['hlc'] as String,
    deviceId: json['deviceId'] as String,
    deleted: json['deleted'] as bool? ?? false,
  );
}

class PositionConflict {
  final int id;
  final String bookId;
  final Map<String, dynamic> ours;
  final Map<String, dynamic> theirs;

  const PositionConflict({
    required this.id,
    required this.bookId,
    required this.ours,
    required this.theirs,
  });

  factory PositionConflict.fromJson(Map<String, dynamic> json) =>
      PositionConflict(
        id: (json['id'] as num).toInt(),
        bookId: json['bookId'] as String,
        ours: (json['ours'] as Map).cast<String, dynamic>(),
        theirs: (json['theirs'] as Map).cast<String, dynamic>(),
      );
}
