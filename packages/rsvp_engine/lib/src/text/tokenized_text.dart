import 'dart:collection';

import '../token.dart';
import '../tokenizer.dart';

/// A block of source text to be tokenized, identified by a stable id.
///
/// Deliberately not the EPUB `Block` type: this package knows nothing about
/// books, so anything with an id and some text can be read.
typedef SourceBlock = ({String id, String text});

/// Where a reader is, in terms that survive re-parsing.
///
/// Never a token index: a tokenizer change would shift every saved position
/// silently. See ADR 0002.
class Locator {
  final String blockId;

  /// Character index into that block's source text.
  final int charOffset;

  /// Normalizer version the offset was computed under.
  final int parserVersion;

  const Locator({
    required this.blockId,
    required this.charOffset,
    required this.parserVersion,
  });

  Map<String, dynamic> toJson() => {
    'blockId': blockId,
    'charOffset': charOffset,
    'parserVersion': parserVersion,
  };

  factory Locator.fromJson(Map<String, dynamic> json) => Locator(
    blockId: json['blockId'] as String,
    charOffset: (json['charOffset'] as num?)?.toInt() ?? 0,
    parserVersion: (json['parserVersion'] as num?)?.toInt() ?? 0,
  );

  @override
  String toString() => 'Locator($blockId @$charOffset v$parserVersion)';

  @override
  bool operator ==(Object other) =>
      other is Locator &&
      other.blockId == blockId &&
      other.charOffset == charOffset &&
      other.parserVersion == parserVersion;

  @override
  int get hashCode => Object.hash(blockId, charOffset, parserVersion);
}

/// Many blocks tokenized into one continuous stream, with the mapping back
/// to source positions retained.
///
/// [PlaybackSession] wants a flat list; persistence and sync want block and
/// offset. This holds both so neither has to know about the other.
class TokenizedText {
  final List<Token> tokens;

  /// Block id for each entry in [_blockStarts], parallel arrays.
  final List<String> _blockIds;

  /// Index into [tokens] where each block's first token sits. Ascending, so
  /// [blockIndexOf] binary-searches rather than scans.
  final List<int> _blockStarts;

  /// Position in [_blockIds] for each id, so a lookup by id does not scan.
  ///
  /// The two lookups that take an id — [indexOf], on every resume and every
  /// conflict candidate, and [startOfBlock], once per table of contents
  /// entry — used `_blockIds.indexOf`, which is linear. Chapter resolution
  /// walks forward from a block that tokenized to nothing, so a book whose
  /// entries land on dropped blocks turned that into a scan per step.
  ///
  /// Built once here rather than lazily: the ids are already in hand, one
  /// map of a thousand-odd entries costs nothing beside the token list it
  /// sits next to, and a lazy field would need a null check on a path that
  /// runs while the reader waits for a book to open.
  final Map<String, int> _blockIndexById;

  final int parserVersion;

  /// [blockIds] is a plain parameter rather than an initializing formal
  /// because the id map is built from it in the same initializer list, and a
  /// field cannot be read there.
  TokenizedText._({
    required this.tokens,
    required List<String> blockIds,
    required this._blockStarts,
    required this.parserVersion,
  }) : _blockIds = blockIds,
       _blockIndexById = _indexById(blockIds);

  /// First position of each id, matching what `List.indexOf` answered before
  /// this map replaced it.
  ///
  /// A map literal would keep the *last* of a repeated id and the scan it
  /// replaces kept the first. Ids are supposed to be unique — `Block.makeId`
  /// derives them from a position within a document, and the golden fixture
  /// asserts no collisions — but this type takes any `(id, text)` pair from
  /// any caller, so the invariant is the caller's and the behaviour under a
  /// broken one should not change silently.
  static Map<String, int> _indexById(List<String> ids) {
    final byId = <String, int>{};
    for (var i = 0; i < ids.length; i++) {
      byId.putIfAbsent(ids[i], () => i);
    }
    return byId;
  }

  /// Tokenize [blocks] in order.
  ///
  /// Blocks that produce no tokens are skipped entirely rather than recorded
  /// as empty ranges, so every id in the map has at least one token.
  factory TokenizedText.from(
    Iterable<SourceBlock> blocks, {
    Tokenizer? tokenizer,
    required int parserVersion,
  }) {
    final tok = tokenizer ?? Tokenizer();

    final tokens = <Token>[];
    final ids = <String>[];
    final starts = <int>[];

    for (final block in blocks) {
      final blockTokens = tok.tokenize(block.text);
      if (blockTokens.isEmpty) continue;

      ids.add(block.id);
      starts.add(tokens.length);
      tokens.addAll(blockTokens);
    }

    return TokenizedText._(
      tokens: tokens,
      blockIds: ids,
      blockStarts: starts,
      parserVersion: parserVersion,
    );
  }

  bool get isEmpty => tokens.isEmpty;
  int get length => tokens.length;
  int get blockCount => _blockIds.length;

  /// Block ids in reading order.
  UnmodifiableListView<String> get blockIds => UnmodifiableListView(_blockIds);

  /// Which block contains [tokenIndex]. Returns -1 when out of range.
  int blockIndexOf(int tokenIndex) {
    if (tokenIndex < 0 || tokenIndex >= tokens.length) return -1;

    var low = 0;
    var high = _blockStarts.length - 1;

    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_blockStarts[mid] <= tokenIndex) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// Locator for the token at [tokenIndex], or null if out of range.
  Locator? locatorAt(int tokenIndex) {
    final block = blockIndexOf(tokenIndex);
    if (block == -1) return null;

    return Locator(
      blockId: _blockIds[block],
      charOffset: tokens[tokenIndex].charOffset,
      parserVersion: parserVersion,
    );
  }

  /// Token index for a stored position.
  ///
  /// Returns null when the block is unknown, which happens if a book was
  /// re-imported with different content. Callers should fall back to the
  /// start rather than guessing.
  ///
  /// A [parserVersion] mismatch is not treated as fatal here: offsets may
  /// still be close enough to be useful, and refusing to resume is worse
  /// than landing a sentence away. Compare [Locator.parserVersion] yourself
  /// if a migration needs to run first.
  int? indexOf(Locator locator) {
    final block = _blockIndexById[locator.blockId];
    if (block == null) return null;

    final start = _blockStarts[block];
    final end = block + 1 < _blockStarts.length
        ? _blockStarts[block + 1]
        : tokens.length;

    // Last token starting at or before the offset. Linear within one block,
    // which is short; binary search would save nothing measurable.
    var found = start;
    for (var i = start; i < end; i++) {
      if (tokens[i].charOffset <= locator.charOffset) {
        found = i;
      } else {
        break;
      }
    }
    return found;
  }

  /// First token index of a block, or null if the block is unknown.
  ///
  /// Unknown covers two cases the caller has to tell apart itself: a block
  /// from a different edition, and a block of this text that tokenized to
  /// nothing and so was never recorded.
  int? startOfBlock(String blockId) {
    final block = _blockIndexById[blockId];
    return block == null ? null : _blockStarts[block];
  }

  /// Fraction of the way through, for a progress indicator.
  double progressAt(int tokenIndex) {
    if (tokens.isEmpty) return 0;
    return ((tokenIndex + 1) / tokens.length).clamp(0.0, 1.0);
  }
}
