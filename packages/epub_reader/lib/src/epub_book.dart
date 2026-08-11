import 'block.dart';
import 'toc.dart';

/// Thrown when a file is not a usable EPUB. Typed so the app can show the
/// reader something specific rather than a stack trace.
class EpubException implements Exception {
  final String message;
  const EpubException(this.message);

  @override
  String toString() => 'EpubException: $message';
}

class EpubMetadata {
  final String title;
  final String? author;

  /// BCP 47 tag from the OPF, such as `lt` or `en-GB`. Used later to pick a
  /// tokenizer abbreviation set.
  final String? language;

  /// Publisher identifier, usually an ISBN or UUID. Not unique enough to key
  /// a library on, but useful for matching duplicates.
  final String? identifier;

  /// Archive path of the cover image, if the book declares one.
  final String? coverHref;

  const EpubMetadata({
    required this.title,
    this.author,
    this.language,
    this.identifier,
    this.coverHref,
  });
}

/// One spine document, normalized.
class EpubDocument {
  /// Archive path, resolved relative to the OPF and percent-decoded.
  final String href;

  /// True when the spine marks this item `linear="no"`: notes, colophons and
  /// other content outside the main reading flow.
  final bool isLinear;

  final List<Block> blocks;

  /// Fragment identifier to index into [blocks].
  ///
  /// Kept per document rather than merged into one book-wide map, because
  /// fragment ids are only unique within a document and two chapters in
  /// different files may well share one.
  final Map<String, int> anchors;

  const EpubDocument({
    required this.href,
    required this.blocks,
    this.anchors = const {},
    this.isLinear = true,
  });
}

class EpubBook {
  final EpubMetadata metadata;

  /// Spine order, including non-linear items.
  final List<EpubDocument> documents;

  /// The book's own table of contents, flattened and resolved to blocks.
  ///
  /// Empty when the book declares none, or when every entry it declares
  /// points somewhere unreadable. Nothing is inferred to fill the gap: see
  /// ADR 0010.
  final List<TocEntry> toc;

  const EpubBook({
    required this.metadata,
    required this.documents,
    this.toc = const [],
  });

  /// Every block in reading order, skipping non-linear documents.
  List<Block> get readingOrder => [
    for (final d in documents)
      if (d.isLinear) ...d.blocks,
  ];

  int get blockCount => readingOrder.length;
}
