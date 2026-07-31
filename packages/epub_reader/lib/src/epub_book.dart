import 'block.dart';

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

  const EpubDocument({
    required this.href,
    required this.blocks,
    this.isLinear = true,
  });
}

class EpubBook {
  final EpubMetadata metadata;

  /// Spine order, including non-linear items.
  final List<EpubDocument> documents;

  const EpubBook({required this.metadata, required this.documents});

  /// Every block in reading order, skipping non-linear documents.
  List<Block> get readingOrder => [
    for (final d in documents)
      if (d.isLinear) ...d.blocks,
  ];

  int get blockCount => readingOrder.length;
}
