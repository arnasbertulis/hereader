/// Bumped whenever normalization changes in a way that shifts character
/// offsets. Stored alongside every locator so old positions can be migrated
/// deliberately rather than silently drifting. See ADR 0002.
const int kParserVersion = 1;

enum BlockKind {
  paragraph,
  heading,
  listItem,
  quote,

  /// A line of verse. Kept distinct because line breaks carry meaning here
  /// and collapsing them would be wrong.
  verse,

  caption,
}

/// One normalized run of readable text.
///
/// [text] is what the tokenizer consumes and what [charOffset] in a locator
/// indexes into. It is never raw markup.
class Block {
  /// Stable across re-parses of the same file: derived from the spine href
  /// and the block's position within that document, never from its content.
  final String id;

  /// Spine item this came from, as written in the OPF manifest.
  final String href;

  /// Zero-based position within the spine item.
  final int index;

  final BlockKind kind;

  /// 1 to 6 for headings, null otherwise.
  final int? headingLevel;

  final String text;

  const Block({
    required this.id,
    required this.href,
    required this.index,
    required this.kind,
    required this.text,
    this.headingLevel,
  });

  static String makeId(String href, int index) =>
      _fnv1a('$href#$index').toRadixString(16);

  @override
  String toString() => 'Block($kind $id "${_preview(text)}")';

  static String _preview(String s) =>
      s.length <= 40 ? s : '${s.substring(0, 40)}...';
}

/// FNV-1a, 64-bit. Chosen over a cryptographic hash because this needs to be
/// deterministic and dependency-free, not collision-resistant against an
/// adversary. Block IDs are namespaced by href, so the practical collision
/// space is one document.
int _fnv1a(String input) {
  const offsetBasis = 0xcbf29ce484222325;
  const prime = 0x100000001b3;

  var hash = offsetBasis;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash;
}
