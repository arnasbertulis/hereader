import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'block.dart';

/// Elements that produce a block of their own.
const _blockTags = {
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'li', 'blockquote', 'figcaption', 'dd', 'dt', 'pre',
};

/// Elements dropped whole, including their text.
///
/// Tables and images are excluded because a table cell read one word at a
/// time loses the structure that made it a table. Recorded as a limitation
/// rather than solved.
const _skipTags = {
  'script', 'style', 'head', 'title', 'noscript',
  'table', 'img', 'svg', 'math', 'figure', 'audio', 'video',
};

final _whitespace = RegExp(r'\s+');

/// Turns one spine document into readable blocks.
///
/// Pure: give it a string of XHTML and an href, get blocks back. No file
/// access, so it tests against string literals rather than fixture EPUBs.
class HtmlNormalizer {
  /// Drop blocks with fewer than this many characters. Catches page numbers,
  /// stray markup artefacts and empty paragraphs used as spacing.
  final int minBlockLength;

  const HtmlNormalizer({this.minBlockLength = 2});

  List<Block> normalize(String source, {required String href}) {
    final document = html_parser.parse(source);
    final body = document.body;
    if (body == null) return const [];

    final blocks = <Block>[];
    _walk(body, href, blocks);
    return blocks;
  }

  void _walk(dom.Element element, String href, List<Block> out) {
    for (final node in element.nodes) {
      if (node is! dom.Element) continue;

      final tag = node.localName?.toLowerCase();
      if (tag == null || _skipTags.contains(tag)) continue;

      if (_isNavigation(node)) continue;

      if (_blockTags.contains(tag)) {
        // A blockquote wrapping paragraphs should yield those paragraphs,
        // not one merged block plus duplicates of its children.
        if (_hasBlockChildren(node)) {
          _walk(node, href, out);
        } else {
          _emit(node, tag, href, out);
        }
        continue;
      }

      // Containers such as div, section and body itself: descend. A div that
      // holds only inline content is still a block, so emit it if nothing
      // deeper would be.
      if (_hasBlockChildren(node)) {
        _walk(node, href, out);
      } else {
        _emit(node, 'p', href, out);
      }
    }
  }

  void _emit(dom.Element element, String tag, String href, List<Block> out) {
    final text = _textOf(element);
    if (text.length < minBlockLength) return;

    final index = out.length;
    out.add(Block(
      id: Block.makeId(href, index),
      href: href,
      index: index,
      kind: _kindOf(tag),
      headingLevel: _headingLevel(tag),
      text: text,
    ));
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

  bool _hasBlockChildren(dom.Element element) => element.children.any((c) {
        final tag = c.localName?.toLowerCase();
        if (tag == null) return false;
        if (_blockTags.contains(tag)) return true;
        if (_skipTags.contains(tag)) return false;
        return _hasBlockChildren(c);
      });

  /// EPUB 3 marks tables of contents and page lists with epub:type. Reading
  /// a table of contents one word at a time is not useful.
  bool _isNavigation(dom.Element element) {
    final tag = element.localName?.toLowerCase();
    if (tag == 'nav') return true;

    final type = element.attributes['epub:type'] ??
        element.attributes['type'] ??
        '';
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
}
