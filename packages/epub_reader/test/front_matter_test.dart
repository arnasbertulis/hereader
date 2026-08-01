import 'package:test/test.dart';
import 'package:epub_reader/epub_reader.dart';

Block _b(String text, {int index = 0}) => Block(
  id: Block.makeId('a.xhtml', index),
  href: 'a.xhtml',
  index: index,
  kind: BlockKind.paragraph,
  text: text,
);

List<Block> _blocks(List<String> texts) => [
  for (var i = 0; i < texts.length; i++) _b(texts[i], index: i),
];

/// Padding so the fifteen percent cap does not dominate short fixtures.
List<String> _prose(int count) => [
  for (var i = 0; i < count; i++)
    'A sentence of ordinary narrative prose, number $i, long enough to be '
        'unmistakable for catalogue metadata.',
];

void main() {
  group('explicit marker', () {
    test('starts on the block after the Gutenberg start line', () {
      final blocks = _blocks([
        'The Project Gutenberg eBook of Romeo and Juliet',
        'Title: Romeo and Juliet',
        '*** START OF THE PROJECT GUTENBERG EBOOK ROMEO AND JULIET ***',
        'THE TRAGEDY OF ROMEO AND JULIET',
        ..._prose(30),
      ]);

      final start = findContentStart(blocks);

      expect(start.blockIndex, 3);
      expect(start.reason, ContentStartReason.explicitMarker);
      expect(start.isConfident, isTrue);
      expect(blocks[start.blockIndex].text, 'THE TRAGEDY OF ROMEO AND JULIET');
    });

    test('accepts the START OF THIS variant', () {
      final blocks = _blocks([
        'Header',
        '*** START OF THIS PROJECT GUTENBERG EBOOK SOMETHING ***',
        ..._prose(30),
      ]);

      expect(
        findContentStart(blocks).reason,
        ContentStartReason.explicitMarker,
      );
      expect(findContentStart(blocks).blockIndex, 2);
    });

    test('is case insensitive', () {
      final blocks = _blocks([
        'Header',
        '*** start of the project gutenberg ebook whatever ***',
        ..._prose(30),
      ]);

      expect(
        findContentStart(blocks).reason,
        ContentStartReason.explicitMarker,
      );
    });

    test('ignores a marker that is the very last block', () {
      final blocks = _blocks([
        ..._prose(30),
        '*** START OF THE PROJECT GUTENBERG EBOOK ***',
      ]);

      // Skipping to nothing would leave an empty book.
      expect(findContentStart(blocks).blockIndex, 0);
    });

    test('ignores a marker buried deep in the text', () {
      // A book quoting the marker mid-way is not front matter.
      final blocks = _blocks([
        ..._prose(50),
        '*** START OF THE PROJECT GUTENBERG EBOOK ***',
        ..._prose(50),
      ]);

      expect(
        findContentStart(blocks).reason,
        isNot(ContentStartReason.explicitMarker),
      );
    });
  });

  group('boilerplate prefixes', () {
    test('skips leading catalogue metadata', () {
      final blocks = _blocks([
        'Title: A Book',
        'Author: A Writer',
        'Release date: January 1, 1900',
        'Language: English',
        ..._prose(40),
      ]);

      final start = findContentStart(blocks);

      expect(start.blockIndex, 4);
      expect(start.reason, ContentStartReason.boilerplateHeuristic);
      expect(start.isConfident, isFalse);
    });

    test('stops at the first block that is not boilerplate', () {
      final blocks = _blocks([
        'Title: A Book',
        'Chapter One',
        'Author: A Writer',
        ..._prose(40),
      ]);

      expect(findContentStart(blocks).blockIndex, 1);
    });

    test('matches a prefix regardless of block length', () {
      // Anchored patterns are safe at any length: prose does not open with
      // "Credits:".
      final blocks = _blocks([
        'Credits: a very long list of volunteer transcribers and proofreaders '
            'whose names run on for rather longer than a hundred and twenty '
            'characters, as these acknowledgement blocks tend to do in books '
            'produced by distributed proofreading projects.',
        ..._prose(40),
      ]);

      expect(findContentStart(blocks).blockIndex, 1);
    });
  });

  group('boilerplate phrases', () {
    test('skips a short rights line', () {
      final blocks = _blocks([
        'Copyright 1923. All rights reserved.',
        ..._prose(40),
      ]);

      expect(findContentStart(blocks).blockIndex, 1);
      expect(
        findContentStart(blocks).reason,
        ContentStartReason.boilerplateHeuristic,
      );
    });

    test('does not skip long prose that mentions a trigger phrase', () {
      final blocks = _blocks([
        'The lawyer explained that the estate remained in the public domain, '
            'a fact which had bothered the family for three generations and '
            'which nobody had thought to question until that afternoon in '
            'the offices above the square, when the youngest of them finally '
            'asked why. It was, she said, a matter of some delicacy, and one '
            'that would take rather longer to explain than any of them had '
            'time for that day. Nobody pressed her further, and the subject '
            'was allowed to lapse for another decade.',
        ..._prose(40),
      ]);

      expect(findContentStart(blocks).blockIndex, 0);
      expect(findContentStart(blocks).reason, ContentStartReason.none);
    });

    test('a paragraph mentioning Project Gutenberg is left alone', () {
      final blocks = _blocks([
        'He had first read the play on Project Gutenberg, on a library '
            'computer with a flickering monitor, and had never quite shaken '
            'the association between Verona and the smell of warm dust that '
            'hung over the reference section on summer afternoons.',
        ..._prose(40),
      ]);

      expect(findContentStart(blocks).blockIndex, 0);
    });
  });

  group('safety limits', () {
    test('never skips more than a fraction of a short book', () {
      // Every block looks like boilerplate; the cap stops a runaway skip.
      final blocks = _blocks([
        for (var i = 0; i < 10; i++) 'Title: Section $i',
      ]);

      expect(findContentStart(blocks).blockIndex, lessThanOrEqualTo(1));
    });
  });

  group('books with no front matter', () {
    test('starts at zero for ordinary prose', () {
      final start = findContentStart(_blocks(_prose(40)));

      expect(start.blockIndex, 0);
      expect(start.reason, ContentStartReason.none);
    });

    test('handles an empty book', () {
      final start = findContentStart(const []);

      expect(start.blockIndex, 0);
      expect(start.reason, ContentStartReason.none);
    });

    test('handles a single block', () {
      expect(findContentStart(_blocks(const ['Just one line.'])).blockIndex, 0);
    });
  });
}
