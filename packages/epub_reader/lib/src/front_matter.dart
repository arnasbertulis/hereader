import 'block.dart';

/// Where a book's actual content appears to begin.
///
/// Nothing is removed. Front matter stays in the block list with its ids
/// intact, so reading positions are unaffected and a reader can rewind into
/// it. This only suggests where to open.
class ContentStart {
  /// Index into the block list. Zero when no front matter was detected.
  final int blockIndex;

  /// Why this index was chosen. Useful in the UI: a confident marker match
  /// can be applied silently, a guess should be easy to undo.
  final ContentStartReason reason;

  const ContentStart(this.blockIndex, this.reason);

  bool get isConfident => reason == ContentStartReason.explicitMarker;
}

enum ContentStartReason {
  /// The book itself marks where its text starts.
  explicitMarker,

  /// Leading blocks matched known boilerplate patterns.
  boilerplateHeuristic,

  /// No front matter found.
  none,
}

/// Project Gutenberg writes this line verbatim before the work begins. It is
/// source-specific by design: guessing structurally is unreliable, and a
/// documented marker is not a guess.
final _gutenbergStart = RegExp(
  r'\*\*\*\s*START OF (THE|THIS) PROJECT GUTENBERG EBOOK',
  caseSensitive: false,
);

/// Anchored to the start of a block. Ordinary prose does not begin this way,
/// so these need no length limit.
final _boilerplatePrefixes = [
  RegExp(r'^Title:\s', caseSensitive: false),
  RegExp(r'^Author:\s', caseSensitive: false),
  RegExp(r'^Release date:\s', caseSensitive: false),
  RegExp(r'^Language:\s', caseSensitive: false),
  RegExp(r'^Credits:\s', caseSensitive: false),
  RegExp(r'^Translator:\s', caseSensitive: false),
  RegExp(r'^Illustrator:\s', caseSensitive: false),
  RegExp(r'^Other information and formats', caseSensitive: false),
];

/// These can appear anywhere in ordinary prose, so a match only counts in a
/// block short enough to be a rights line rather than a paragraph.
final _boilerplatePhrases = [
  RegExp(r'\bProject Gutenberg\b', caseSensitive: false),
  RegExp(r'\bpublic domain\b', caseSensitive: false),
  RegExp(r'\ball rights reserved\b', caseSensitive: false),
];

/// A phrase match in a block longer than this is assumed to be prose.
///
/// Deliberately tight. A novel's opening paragraph can mention copyright or
/// the public domain, and skipping it would be far worse than showing the
/// reader one line of rights boilerplate.
const _maxPhraseLength = 120;

/// Never suggest skipping more than this fraction of a book. A short work
/// whose opening resembles boilerplate should still open at the start.
const _maxSkipFraction = 0.15;

/// Finds where [blocks] stop being front matter.
ContentStart findContentStart(List<Block> blocks) {
  if (blocks.isEmpty) return const ContentStart(0, ContentStartReason.none);

  final limit = (blocks.length * _maxSkipFraction).floor();

  // An explicit marker wins outright.
  for (var i = 0; i < blocks.length && i <= limit; i++) {
    if (_gutenbergStart.hasMatch(blocks[i].text)) {
      final next = i + 1;
      if (next < blocks.length) {
        return ContentStart(next, ContentStartReason.explicitMarker);
      }
    }
  }

  // Otherwise walk past leading blocks that look like catalogue metadata,
  // stopping at the first that does not.
  var i = 0;
  while (i < blocks.length && i < limit && _looksLikeBoilerplate(blocks[i])) {
    i++;
  }

  return i == 0
      ? const ContentStart(0, ContentStartReason.none)
      : ContentStart(i, ContentStartReason.boilerplateHeuristic);
}

bool _looksLikeBoilerplate(Block block) {
  final text = block.text;

  if (_boilerplatePrefixes.any((pattern) => pattern.hasMatch(text))) {
    return true;
  }

  return text.length <= _maxPhraseLength &&
      _boilerplatePhrases.any((pattern) => pattern.hasMatch(text));
}
