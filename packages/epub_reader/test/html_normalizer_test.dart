import 'package:test/test.dart';
import 'package:epub_reader/epub_reader.dart';

const _href = 'OEBPS/chapter1.xhtml';

List<Block> _blocks(String body, {String href = _href}) =>
    const HtmlNormalizer().normalize('<html><body>$body</body></html>',
        href: href);

List<String> _texts(String body) => _blocks(body).map((b) => b.text).toList();

void main() {
  group('basic extraction', () {
    test('paragraphs become blocks in document order', () {
      expect(
        _texts('<p>First.</p><p>Second.</p><p>Third.</p>'),
        ['First.', 'Second.', 'Third.'],
      );
    });

    test('an empty document yields nothing', () {
      expect(_blocks(''), isEmpty);
      expect(const HtmlNormalizer().normalize('', href: _href), isEmpty);
    });

    test('blocks carry their href and index', () {
      final blocks = _blocks('<p>One.</p><p>Two.</p>');

      expect(blocks[0].href, _href);
      expect(blocks[0].index, 0);
      expect(blocks[1].index, 1);
    });

    test('headings keep their level', () {
      final blocks = _blocks('<h1>Part One</h1><h3>A section</h3>');

      expect(blocks[0].kind, BlockKind.heading);
      expect(blocks[0].headingLevel, 1);
      expect(blocks[1].headingLevel, 3);
    });

    test('paragraphs have no heading level', () {
      expect(_blocks('<p>Text.</p>').single.headingLevel, isNull);
    });

    test('list items are marked as such', () {
      final blocks = _blocks('<ul><li>Alpha</li><li>Beta</li></ul>');

      expect(blocks.length, 2);
      expect(blocks.every((b) => b.kind == BlockKind.listItem), isTrue);
    });
  });

  group('whitespace normalization', () {
    test('collapses newlines and runs of spaces', () {
      expect(
        _texts('<p>One\n   two\t\tthree</p>'),
        ['One two three'],
      );
    });

    test('treats a line break as a space', () {
      expect(_texts('<p>One<br/>two</p>'), ['One two']);
    });

    test('trims leading and trailing whitespace', () {
      expect(_texts('<p>   Padded.   </p>'), ['Padded.']);
    });

    test('flattens inline markup into one string', () {
      expect(
        _texts('<p>A <em>strong</em> and <b>bold</b> claim.</p>'),
        ['A strong and bold claim.'],
      );
    });

    test('decodes entities', () {
      expect(_texts('<p>Smith &amp; Sons &mdash; est. 1890</p>'),
          ['Smith & Sons — est. 1890']);
    });

    test('preserves Lithuanian diacritics', () {
      expect(
        _texts('<p>Nebeprisikiškiakopūsteliaujantiesiems ąčęėįšųūž</p>'),
        ['Nebeprisikiškiakopūsteliaujantiesiems ąčęėįšųūž'],
      );
    });

    test('drops empty and whitespace-only blocks', () {
      expect(_texts('<p>Real.</p><p></p><p>   </p><p>\n</p>'), ['Real.']);
    });
  });

  group('nesting', () {
    test('a blockquote of paragraphs yields those paragraphs', () {
      final blocks = _blocks(
        '<blockquote><p>Quoted line.</p><p>Second line.</p></blockquote>',
      );

      expect(blocks.map((b) => b.text).toList(),
          ['Quoted line.', 'Second line.']);
      // The wrapper is not emitted, so its kind is lost. Reading a quotation
      // one word at a time does not convey the quoting anyway.
      expect(blocks.every((b) => b.kind == BlockKind.paragraph), isTrue);
    });

    test('a blockquote of inline text stays one quote block', () {
      final block = _blocks('<blockquote>Bare quoted text.</blockquote>').single;

      expect(block.kind, BlockKind.quote);
      expect(block.text, 'Bare quoted text.');
    });

    test('a wrapper div does not duplicate its paragraphs', () {
      expect(
        _texts('<div><div><p>Deep.</p></div></div>'),
        ['Deep.'],
      );
    });

    test('a div holding only inline text becomes a paragraph', () {
      // Some books use divs where paragraphs belong.
      final block = _blocks('<div>Styled as a paragraph.</div>').single;

      expect(block.kind, BlockKind.paragraph);
      expect(block.text, 'Styled as a paragraph.');
    });

    test('a list item containing a paragraph loses the list kind', () {
      // Known behaviour: the walk descends to the innermost block.
      final block =
          _blocks('<ul><li><p>Wrapped item</p></li></ul>').single;

      expect(block.kind, BlockKind.paragraph);
    });
  });

  group('skipped content', () {
    test('drops scripts and styles', () {
      expect(
        _texts('<p>Kept.</p><script>alert(1)</script><style>p{}</style>'),
        ['Kept.'],
      );
    });

    test('drops tables entirely', () {
      expect(
        _texts('<p>Before.</p><table><tr><td>Cell</td></tr></table>'),
        ['Before.'],
      );
    });

    test('drops images without losing surrounding text', () {
      expect(
        _texts('<p>Look <img src="x.png" alt="ignored"/> here.</p>'),
        ['Look here.'],
      );
    });

    test('drops a nav element', () {
      expect(
        _texts('<nav><p>Table of contents</p></nav><p>Chapter one.</p>'),
        ['Chapter one.'],
      );
    });

    test('drops a section marked as a table of contents', () {
      expect(
        _texts('<section epub:type="toc"><p>Contents</p></section>'
            '<p>Real text.</p>'),
        ['Real text.'],
      );
    });

    test('figures are dropped, and their captions with them', () {
      // Current behaviour: figure is skipped whole, so figcaption is never
      // reached despite being a block tag. Change _skipTags if captions
      // should survive.
      expect(
        _texts('<figure><img src="a.png"/><figcaption>A caption</figcaption>'
            '</figure><p>Body.</p>'),
        ['Body.'],
      );
    });
  });

  group('block ids', () {
    test('are stable across repeated parses', () {
      const source = '<p>One.</p><p>Two.</p>';

      final first = _blocks(source).map((b) => b.id).toList();
      final second = _blocks(source).map((b) => b.id).toList();

      expect(first, equals(second));
    });

    test('differ between documents at the same position', () {
      final a = _blocks('<p>Same text.</p>', href: 'a.xhtml').single;
      final b = _blocks('<p>Same text.</p>', href: 'b.xhtml').single;

      expect(a.id, isNot(b.id));
    });

    test('differ between positions in one document', () {
      final blocks = _blocks('<p>Same.</p><p>Same.</p>');

      // Identical text, different position: ids must not collide, which is
      // why they derive from position rather than content.
      expect(blocks[0].id, isNot(blocks[1].id));
    });

    test('do not change when unrelated text is edited', () {
      final before = _blocks('<p>Original.</p><p>Second.</p>');
      final after = _blocks('<p>Corrected typo.</p><p>Second.</p>');

      expect(after[1].id, before[1].id);
    });

    test('are unique across a document', () {
      final ids = _blocks(List.filled(50, '<p>Line of text.</p>').join())
          .map((b) => b.id)
          .toList();

      expect(ids.toSet().length, ids.length);
    });
  });

  group('offsets into normalized text', () {
    test('block text is what a locator offset indexes into', () {
      // The offset stored in a locator counts characters in Block.text, not
      // in the source markup. See ADR 0002.
      final block = _blocks('<p>The  <em>quick</em>\nbrown fox.</p>').single;

      expect(block.text, 'The quick brown fox.');
      expect(block.text.substring(4, 9), 'quick');
    });
  });

  group('parser version', () {
    test('is recorded so offsets can be migrated', () {
      expect(kParserVersion, greaterThan(0));
    });
  });
}
