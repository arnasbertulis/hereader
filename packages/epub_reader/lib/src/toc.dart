/// One entry from a book's own table of contents, resolved to a block.
///
/// Deliberately not an href and a fragment. A caller navigating a book works
/// in blocks and offsets (ADR 0002); handing it a URL would push the job of
/// resolving that URL into every caller, and only this package knows how the
/// document was normalized.
class TocEntry {
  final String title;

  /// The block this entry lands on.
  ///
  /// Always a block that exists in the parsed book. Entries pointing at a
  /// document that produced no text, or at one outside the reading flow, are
  /// dropped rather than carried with an id nothing can resolve.
  final String blockId;

  /// Nesting in the source table of contents. Zero is top level; a scene
  /// inside an act is one.
  ///
  /// Flattened rather than kept as a tree. A reader navigating by chapter
  /// wants one scrollable list, and indentation carries the structure
  /// perfectly well at the two or three levels books actually use.
  final int depth;

  const TocEntry({
    required this.title,
    required this.blockId,
    required this.depth,
  });

  @override
  String toString() => 'TocEntry(${'  ' * depth}$title -> $blockId)';
}
