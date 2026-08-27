import 'package:app/net/http_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('HttpTransport.readJson', () {
    final transport = HttpTransport(http.Client());

    test('decodes an empty body to an empty map', () {
      final response = http.Response('', 200);
      expect(transport.readJson(response), <String, dynamic>{});
    });

    test('decodes an empty body to an empty items list when expectList', () {
      final response = http.Response('', 200);
      expect(transport.readJson(response, expectList: true), {'items': []});
    });

    test('wraps a bare top-level array as items', () {
      final response = http.Response('[1,2,3]', 200);
      expect(transport.readJson(response, expectList: true), {
        'items': [1, 2, 3],
      });
    });

    test('decodes an object body unchanged', () {
      final response = http.Response('{"a":1}', 200);
      expect(transport.readJson(response), {'a': 1});
    });

    test('throws ApiException with the RFC 9457 detail on a >=400 status', () {
      final response = http.Response('{"detail":"Not found."}', 404);
      expect(
        () => transport.readJson(response),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', 'Not found.'),
        ),
      );
    });

    test('falls back to a status-code message on a non-problem body', () {
      final response = http.Response('not json', 500);
      expect(
        () => transport.readJson(response),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'The server returned 500.',
          ),
        ),
      );
    });
  });
}
