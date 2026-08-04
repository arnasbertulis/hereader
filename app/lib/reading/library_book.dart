import 'package:epub_reader/epub_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// A book the reader has imported.
class LibraryBook {
  /// Stable across devices: the book's own identifier where it has one,
  /// otherwise its title and author.
  final String id;

  final String title;
  final String? author;
  final String? language;

  final TokenizedText text;

  /// Where the reader last was, or null if never opened.
  final Locator? position;

  /// Token index where the book's own text appears to begin. Front matter is
  /// still present and reachable by rewinding; this only decides where an
  /// unread book opens.
  final int contentStartIndex;

  /// Why [contentStartIndex] is where it is. A guess should be easy for the
  /// reader to undo; a marker the book itself provides need not be.
  final ContentStartReason contentStartReason;

  const LibraryBook({
    required this.id,
    required this.title,
    required this.text,
    this.author,
    this.language,
    this.position,
    this.contentStartIndex = 0,
    this.contentStartReason = ContentStartReason.none,
  });

  LibraryBook withPosition(Locator? next) => LibraryBook(
    id: id,
    title: title,
    author: author,
    language: language,
    text: text,
    position: next,
    contentStartIndex: contentStartIndex,
    contentStartReason: contentStartReason,
  );

  /// True when front matter was skipped on a guess rather than on a marker
  /// the book supplied. The reader should be offered a way back.
  bool get skippedFrontMatterOnAGuess =>
      contentStartReason == ContentStartReason.boilerplateHeuristic;

  /// True when a stored position names a block this copy of the book does
  /// not contain.
  ///
  /// Happens when a book is re-imported under a different `kParserVersion`,
  /// or when a position synced from a device holding a different edition.
  /// Worth reporting rather than silently restarting: a reader who appears
  /// to have lost their place has no way to tell that from a bug.
  bool get positionUnresolvable =>
      position != null && text.indexOf(position!) == null;

  /// Token to resume from.
  ///
  /// An unread book opens past the front matter. A stored position wins over
  /// that, and falls back to it when the position cannot be resolved.
  int get resumeIndex {
    if (position == null) return contentStartIndex;
    return text.indexOf(position!) ?? contentStartIndex;
  }

  double get progress => position == null ? 0 : text.progressAt(resumeIndex);
}

/// Parsed on a background isolate. Top-level because [compute] cannot send a
/// closure.
LibraryBook _parseBook(Uint8List bytes) {
  final book = const EpubParser().parse(bytes);
  final blocks = book.readingOrder;

  final text = TokenizedText.from(
    blocks.map((b) => (id: b.id, text: b.text)),
    tokenizer: _tokenizerFor(book.metadata.language),
    parserVersion: kParserVersion,
  );

  if (text.isEmpty) {
    throw const EpubException('The book contains no readable words.');
  }

  final start = findContentStart(blocks);

  // Blocks that tokenize to nothing are dropped from the stream, so the
  // suggested block may have no tokens of its own. Fall back to the start
  // rather than guessing at a nearby one.
  final startIndex = start.blockIndex == 0
      ? 0
      : text.startOfBlock(blocks[start.blockIndex].id) ?? 0;

  return LibraryBook(
    id: _idFor(book.metadata),
    title: book.metadata.title,
    author: book.metadata.author,
    language: book.metadata.language,
    text: text,
    contentStartIndex: startIndex,
    contentStartReason: startIndex == 0
        ? ContentStartReason.none
        : start.reason,
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
