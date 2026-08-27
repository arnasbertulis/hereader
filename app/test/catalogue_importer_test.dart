import 'dart:convert';
import 'dart:typed_data';

import 'package:app/catalogue/catalogue_importer.dart';
import 'package:app/sync/api_client.dart';
import 'package:epub_reader/epub_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeCatalogueClient client;
  late CatalogueImporter importer;

  setUp(() {
    client = FakeCatalogueClient();
    importer = CatalogueImporter(client: client);
  });

  test('downloads the requested Catalogue Entry before parsing', () async {
    client.downloadBytes = Uint8List.fromList(utf8.encode('not an epub'));

    await expectLater(
      () => importer.import(1513),
      throwsA(isA<EpubException>()),
    );

    expect(client.downloadRequests, [1513]);
  });

  test(
    'a download that does not parse as an EPUB throws EpubException and '
    'writes nothing — the caller only reaches its own addBook on success',
    () async {
      client.downloadBytes = Uint8List.fromList(utf8.encode('truncated'));

      expect(() => importer.import(1513), throwsA(isA<EpubException>()));
    },
  );

  test(
    'a network failure surfaces as NetworkException, not swallowed',
    () async {
      client.nextError = const NetworkException('Could not reach the server.');

      await expectLater(
        () => importer.import(1513),
        throwsA(isA<NetworkException>()),
      );
    },
  );

  test(
    'a refusal from the service surfaces as ApiException, not swallowed',
    () async {
      client.nextError = const ApiException(
        404,
        'No such book in the Catalogue.',
      );

      await expectLater(
        () => importer.import(1513),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
