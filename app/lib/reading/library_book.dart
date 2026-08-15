import 'package:epub_reader/epub_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// A place in the book the reader can jump to by name.
///
/// A token index rather than a locator, because this is not a position that
/// is stored or synced — it is resolved fresh every time the book is parsed
/// and is only ever handed to [PlaybackSession.seekToIndex]. Persisting one
/// would mean keeping a copy of the table of contents in the database and
/// migrating it whenever normalization changed.
class Chapter {
  final String title;

  /// Nesting in the book's own table of contents. Zero is top level.
  final int depth;

  /// First token of the chapter, in this parse of this book.
  final int tokenIndex;

  const Chapter({
    required this.title,
    required this.depth,
    required this.tokenIndex,
  });
}

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

  /// The book's own table of contents, resolved to token indices.
  ///
  /// Empty when the book declares none, or when nothing it declares survives
  /// resolution. Nothing is inferred from headings to fill the gap: see
  /// ADR 0010.
  final List<Chapter> chapters;

  /// The book's cover image, or null when it declares none.
  ///
  /// Carried out of the parse so the import that stores the book can store
  /// the cover in the same transaction. Nothing draws it yet.
  final Uint8List? coverBytes;

  const LibraryBook({
    required this.id,
    required this.title,
    required this.text,
    this.author,
    this.language,
    this.position,
    this.contentStartIndex = 0,
    this.contentStartReason = ContentStartReason.none,
    this.chapters = const [],
    this.coverBytes,
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
    chapters: chapters,
    coverBytes: coverBytes,
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
}

/// Parses and tokenizes a book. Top-level because [compute] cannot send a
/// closure.
///
/// Off the UI isolate on Android and Windows only. `compute()` does not spawn
/// an isolate on Flutter web: it calls the function directly and wraps the
/// result in a Future, so on the one target with no second thread to fall
/// back to, this blocks the thread that draws frames. Both expensive passes
/// are in here — `mainLoop` in `epub_parser` and `tokenize` — and together
/// they are a few hundred milliseconds on a novel.
///
/// Not worked around. A real web worker needs its own compiled entry point,
/// and chunking the walk with yields would reshape the parser for one target;
/// which of those is worth doing depends on how much of the web stall is
/// actually parsing, which has not been measured in a profile build.
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
    chapters: chaptersOf(book, text),
    coverBytes: book.coverBytes,
  );
}

/// Turns the parsed table of contents into something the reader can jump to.
///
/// The parser resolves each entry to a block; this resolves that block to a
/// token, which is what playback moves in.
///
/// `TokenizedText.from` drops blocks that produce no tokens, so
/// `startOfBlock` can return null for a block that genuinely exists — the
/// same condition `contentStartIndex` already guards against above. Here the
/// search walks forward to the first block that did produce tokens. Landing
/// a line late is invisible to the reader; dropping the chapter is not.
///
/// Public because it is the one piece of this file worth testing on its own.
/// Everything else here runs only behind [compute], which a widget test
/// cannot reach without spawning an isolate and a real EPUB.
List<Chapter> chaptersOf(EpubBook book, TokenizedText text) {
  if (book.toc.isEmpty) return const [];

  final blocks = book.readingOrder;

  final blockPositions = <String, int>{
    for (var i = 0; i < blocks.length; i++) blocks[i].id: i,
  };

  final chapters = <Chapter>[];

  for (final entry in book.toc) {
    final start = blockPositions[entry.blockId];
    if (start == null) continue;

    int? tokenIndex;
    for (var i = start; i < blocks.length; i++) {
      tokenIndex = text.startOfBlock(blocks[i].id);
      if (tokenIndex != null) break;
    }
    if (tokenIndex == null) continue;

    chapters.add(
      Chapter(title: entry.title, depth: entry.depth, tokenIndex: tokenIndex),
    );
  }

  return chapters;
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

  /// Parses [bytes] off the UI isolate on native targets, and on it on web.
  ///
  /// See the note on [_parseBook]: `compute()` runs inline in a browser. The
  /// asymmetry is deliberate to leave visible rather than hidden behind a
  /// wrapper that claims to offload everywhere.
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
