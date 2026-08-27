import 'dart:convert';

import 'package:http/http.dart' as http;

/// Something the API said no to.
class ApiException implements Exception {
  final int statusCode;

  /// Safe to show a reader: the service returns RFC 9457 problem details
  /// with a human-readable message.
  final String message;

  const ApiException(this.statusCode, this.message);

  bool get isUnauthorized => statusCode == 401;
  bool get isConflict => statusCode == 409;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// The network was unreachable, rather than the service refusing.
///
/// Distinct from [ApiException] because the responses differ: a network
/// failure means leave the outbox alone and try later, while a rejection
/// means this event will never succeed and should be parked.
class NetworkException implements Exception {
  final String message;
  const NetworkException(this.message);

  @override
  String toString() => 'NetworkException: $message';
}

/// The transport underneath both `ApiClient` and `CatalogueClient`: issue a
/// request, map a transport failure to [NetworkException], map a >=400
/// status to [ApiException] with the server's message extracted the same
/// way, decode an empty body to `const {}`, and wrap a bare top-level array
/// so a caller sees one return type.
///
/// Carries no notion of auth — `ApiClient` layers its bearer token and
/// refresh-on-401 retry on top of [send], since `CatalogueClient` has
/// neither (every `/catalogue/**` route is `permitAll`).
class HttpTransport {
  final http.Client _http;

  static const timeout = Duration(seconds: 15);

  HttpTransport(this._http);

  /// Issues [method] against [uri]. Does not interpret the status code, so
  /// a caller can act on one (a 401 retry) before [readJson] would throw on
  /// it.
  Future<http.Response> send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Map<String, dynamic>? jsonBody,
  }) async {
    final allHeaders = <String, String>{
      if (jsonBody != null) 'Content-Type': 'application/json',
      ...?headers,
    };

    try {
      final request = http.Request(method, uri)..headers.addAll(allHeaders);
      if (jsonBody != null) request.body = jsonEncode(jsonBody);

      return await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      );
    } catch (e) {
      // Unreachable, refused, timed out: all the same to a caller, which
      // should leave its work queued and try later.
      throw const NetworkException('Could not reach the server.');
    }
  }

  /// Throws [ApiException] for a >=400 [response], otherwise returns it
  /// unchanged.
  http.Response checkStatus(http.Response response) {
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, _apiErrorMessage(response));
    }
    return response;
  }

  /// [checkStatus], then decodes the body: empty to `const {}` (or, when
  /// [expectList] is set, `{'items': []}` — an absent list is empty, not
  /// absent), a bare top-level array wrapped as `{'items': ...}`.
  Map<String, dynamic> readJson(
    http.Response response, {
    bool expectList = false,
  }) {
    checkStatus(response);

    if (response.body.isEmpty) return expectList ? {'items': []} : const {};
    final decoded = jsonDecode(response.body);

    if (expectList) return {'items': decoded};
    return decoded as Map<String, dynamic>;
  }

  void dispose() => _http.close();
}

/// The RFC 9457 problem-detail message on [response], or a fallback naming
/// its status code.
String _apiErrorMessage(http.Response response) {
  try {
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['detail'] is String) {
      return decoded['detail'] as String;
    }
  } catch (_) {
    // Not JSON, or not a problem detail. Fall through.
  }
  return 'The server returned ${response.statusCode}.';
}
