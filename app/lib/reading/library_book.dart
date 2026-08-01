import 'package:epub_reader/epub_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// A book the reader has imported.
///
/// Holds the parsed text in memory for now. Persistence replaces this with a
/// row plus the file on disk; the shape stays the same.
class LibraryBook {
  /// Stable across restarts once persistence lands: derived from the book's
  /// own identifier where it has one, otherwise its title and author.
  final String id;

  final String title;
  final String? author;
  final String? language;

  final TokenizedText text;

  /// Where the reader last was, or null if never opened.
  final Locator? position;

  const LibraryBook({
    required this.id,
    required this.title,
    required this.text,
    this.author,
    this.language,
    this.position,
  });

  LibraryBook withPosition(Locator? next) => LibraryBook(
    id: id,
    title: title,
    author: author,
    language: language,
    text: text,
    position: next,
  );

  /// Token to resume from. Falls back to the start when the stored position
  /// refers to a block this copy of the book does not have.
  int get resumeIndex {
    if (position == null) return 0;
    return text.indexOf(position!) ?? 0;
  }

  double get progress => position == null ? 0 : text.progressAt(resumeIndex);
}

/// Parsed on a background isolate. Top-level because [compute] cannot send a
/// closure.
LibraryBook _parseBook(Uint8List bytes) {
  final book = const EpubParser().parse(bytes);

  final text = TokenizedText.from(
    book.readingOrder.map((b) => (id: b.id, text: b.text)),
    tokenizer: _tokenizerFor(book.metadata.language),
    parserVersion: kParserVersion,
  );

  if (text.isEmpty) {
    throw const EpubException('The book contains no readable words.');
  }

  return LibraryBook(
    id: _idFor(book.metadata),
    title: book.metadata.title,
    author: book.metadata.author,
    language: book.metadata.language,
    text: text,
  );
}

/// Abbreviation handling is language-specific. Only the default set exists
/// today, so this is a seam rather than a feature.
Tokenizer _tokenizerFor(String? language) => Tokenizer();

String _idFor(EpubMetadata metadata) {
  final identifier = metadata.identifier;
  if (identifier != null && identifier.isNotEmpty) return identifier;
  return '${metadata.title}|${metadata.author ?? ""}';
}

/// Imports EPUB files into the library.
class BookImporter {
  const BookImporter();

  /// Parses [bytes] off the UI isolate.
  ///
  /// Throws [EpubException] with a message suitable for showing the reader.
  Future<LibraryBook> import(Uint8List bytes) async {
    try {
      return await compute(_parseBook, bytes);
    } on EpubException {
      rethrow;
    } catch (e) {
      throw const EpubException('The file could not be read as an EPUB.');
    }
  }
}
