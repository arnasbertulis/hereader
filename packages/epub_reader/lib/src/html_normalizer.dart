import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'block.dart';

/// Elements that produce a block of their own.
const _blockTags = {
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'li',
  'blockquote',
  'figcaption',
  'dd',
  'dt',
  'pre',
};

/// Elements dropped whole, including their text.
///
/// Tables and images are excluded because a table cell read one word at a
/// time loses the structure that made it a table. Recorded as a limitation
/// rather than solved.
const _skipTags = {
  'script',
  'style',
  'head',
  'title',
  'noscript',
  'table',
  'img',
  'svg',
  'math',
  'figure',
  'audio',
  'video',
};

final _whitespace = RegExp(r'\s+');

/// One spine document reduced to readable blocks, with the fragment
/// identifiers that point into them.
///
/// The two travel together because one walk produces both. A table of
/// contents entry is an href and a fragment; without [anchors] every entry
/// pointing into the same document resolves to that document's first block,
/// which for a book whose acts and scenes share a file means every chapter
/// jumping to the same place.
class NormalizedDocument {
  final List<Block> blocks;

  /// Fragment identifier from the source markup, to the index in [blocks]
  /// that fragment lands on.
  ///
  /// A fragment can sit on the block element itself, on a container that
  /// wraps several blocks, or on an empty inline anchor inside one. All
  /// three resolve to the block whose text the reader would see.
  final Map<String, int> anchors;

  const NormalizedDocument({required this.blocks, required this.anchors});

  static const empty = NormalizedDocument(blocks: [], anchors: {});
}

/// Turns one spine document into readable blocks.
///
/// Pure: give it a string of XHTML and an href, get blocks back. No file
/// access, so it tests against string literals rather than fixture EPUBs.
class HtmlNormalizer {
  /// Drop blocks with fewer than this many characters. Catches page numbers,
  /// stray markup artefacts and empty paragraphs used as spacing.
  final int minBlockLength;

  const HtmlNormalizer({this.minBlockLength = 2});

  NormalizedDocument normalize(String source, {required String href}) {
    final document = html_parser.parse(source);
    final body = document.body;
    if (body == null) return NormalizedDocument.empty;

    final walk = _Walk(href: href, minBlockLength: minBlockLength);
    walk.descend(body);

    return NormalizedDocument(blocks: walk.blocks, anchors: walk.anchors);
  }
}

/// One pass over one document.
///
/// A class rather than functions threading an accumulator, because anchors
/// have to be carried forward across blocks that get dropped, and that state
/// is easier to follow held in one place than passed through parameters.
class _Walk {
  final String href;
  final int minBlockLength;

  final List<Block> blocks = [];
  final Map<String, int> anchors = {};

  /// Ids seen on elements that have not yet produced a block.
  ///
  /// Held rather than resolved immediately because the element carrying the
  /// id is often not the element carrying the text: a chapter's fragment
  /// usually sits on the `div` that wraps it. Whatever block comes out next
  /// is the one a reader following that fragment should land on.
  final List<String> _pending = [];

  _Walk({required this.href, required this.minBlockLength});

  void descend(dom.Element element) {
    for (final node in element.nodes) {
      if (node is! dom.Element) continue;

      final tag = node.localName?.toLowerCase();
      if (tag == null || _skipTags.contains(tag)) continue;

      if (_isNavigation(node)) continue;

      _hold(node);

      if (_blockTags.contains(tag)) {
        // A blockquote wrapping paragraphs should yield those paragraphs,
        // not one merged block plus duplicates of its children.
        if (_hasBlockChildren(node)) {
          descend(node);
        } else {
          _emit(node, tag);
        }
        continue;
      }

      // Containers such as div, section and body itself: descend. A div that
      // holds only inline content is still a block, so emit it if nothing
      // deeper would be.
      if (_hasBlockChildren(node)) {
        descend(node);
      } else {
        _emit(node, 'p');
      }
    }
  }

  void _hold(dom.Element element) {
    final id = element.attributes['id'];
    if (id != null && id.isNotEmpty) _pending.add(id);
  }

  void _emit(dom.Element element, String tag) {
    // Ids below this element point at text inside it. An empty `<a id=...>`
    // used as a jump target inside a heading is the common shape, and the
    // heading is what the reader wants.
    _holdDescendants(element);

    final text = _textOf(element);
    if (text.length < minBlockLength) {
      // The block goes, the anchors stay pending. A fragment landing on a
      // spacer paragraph should reach the next real text rather than
      // nothing at all.
      return;
    }

    final index = blocks.length;

    // First claim wins. A container and the heading inside it both point at
    // the same block, and nothing further down should move an id that has
    // already resolved.
    for (final id in _pending) {
      anchors.putIfAbsent(id, () => index);
    }
    _pending.clear();

    blocks.add(
      Block(
        id: Block.makeId(href, index),
        href: href,
        index: index,
        kind: _kindOf(tag),
        headingLevel: _headingLevel(tag),
        text: text,
      ),
    );
  }

  void _holdDescendants(dom.Element element) {
    for (final child in element.children) {
      _hold(child);
      _holdDescendants(child);
    }
  }

  /// Collapses all whitespace to single spaces. Line breaks inside a
  /// paragraph carry no meaning in reflowable EPUB, and the tokenizer
  /// classifies pauses from punctuation instead.
  String _textOf(dom.Element element) {
    final buffer = StringBuffer();
    _collect(element, buffer);
    return buffer.toString().replaceAll(_whitespace, ' ').trim();
  }

  void _collect(dom.Node node, StringBuffer buffer) {
    for (final child in node.nodes) {
      if (child is dom.Text) {
        buffer.write(child.text);
      } else if (child is dom.Element) {
        final tag = child.localName?.toLowerCase();
        if (tag == null || _skipTags.contains(tag)) continue;
        if (tag == 'br') {
          buffer.write(' ');
          continue;
        }
        _collect(child, buffer);
      }
    }
  }
}

bool _hasBlockChildren(dom.Element element) => element.children.any((c) {
  final tag = c.localName?.toLowerCase();
  if (tag == null) return false;
  if (_blockTags.contains(tag)) return true;
  if (_skipTags.contains(tag)) return false;
  return _hasBlockChildren(c);
});

/// EPUB 3 marks tables of contents and page lists with epub:type. Reading a
/// table of contents one word at a time is not useful.
bool _isNavigation(dom.Element element) {
  final tag = element.localName?.toLowerCase();
  if (tag == 'nav') return true;

  final type =
      element.attributes['epub:type'] ?? element.attributes['type'] ?? '';
  return type.contains('toc') ||
      type.contains('landmarks') ||
      type.contains('page-list');
}

BlockKind _kindOf(String tag) => switch (tag) {
  'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6' => BlockKind.heading,
  'li' => BlockKind.listItem,
  'blockquote' => BlockKind.quote,
  'figcaption' => BlockKind.caption,
  'pre' => BlockKind.verse,
  _ => BlockKind.paragraph,
};

int? _headingLevel(String tag) =>
    tag.length == 2 && tag.startsWith('h') ? int.tryParse(tag[1]) : null;
