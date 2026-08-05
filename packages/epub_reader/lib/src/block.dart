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

/// FNV-1a, 32-bit. Chosen over 64-bit so this compiles correctly for web:
/// dart2js represents `int` as a JS double, exact only up to 2^53, and a
/// 64-bit hash's arithmetic exceeds that. Block IDs are namespaced by href,
/// so 32 bits (~4.3 billion values) is nowhere near collision territory for
/// a single document's block count.
int _fnv1a(String input) {
  const offsetBasis = 0x811c9dc5;
  const mask32 = 0xFFFFFFFF;

  var hash = offsetBasis;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    // hash *= 0x01000193 (16777619), rewritten as shifts and adds.
    // Each `<<` is an exact 32-bit bitwise op in JS regardless of operand
    // size; plain `*` is a floating-point multiply, only exact below 2^53.
    // This decomposition avoids that precision loss entirely rather than
    // risking it for large hash values.
    hash =
        (hash +
            (hash << 1) +
            (hash << 4) +
            (hash << 7) +
            (hash << 8) +
            (hash << 24)) &
        mask32;
  }
  return hash;
}
