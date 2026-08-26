import 'dart:typed_data';

import '../reading/library_book.dart';
import 'catalogue_client.dart';

/// Turns a Catalogue Entry into a [LibraryBook], the way [BookImporter]
/// already turns a hand-picked file into one — this only adds where the
/// bytes come from.
///
/// Downloads before parsing, and hands back nothing until the parse
/// succeeds: [BookImporter.import] already refuses a corrupt or truncated
/// archive by throwing [EpubException], and this class adds no path around
/// that check. A caller that only writes to the Library on success — as
/// `library_screen.dart`'s manual import already does — can therefore never
/// turn a partial download into a Book.
class CatalogueImporter {
  final CatalogueClient client;
  final BookImporter bookImporter;

  const CatalogueImporter({
    required this.client,
    this.bookImporter = const BookImporter(),
  });

  /// Downloads and parses Catalogue Entry [gutenbergId].
  ///
  /// Throws [NetworkException] when the service is unreachable,
  /// [ApiException] when it refuses the request, and [EpubException] when
  /// the downloaded bytes do not parse as a book.
  Future<LibraryBook> import(int gutenbergId) async {
    final Uint8List bytes = await client.download(gutenbergId);
    return bookImporter.import(bytes);
  }
}
