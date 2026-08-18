import 'package:rsvp_engine/rsvp_engine.dart';
import 'package:test/test.dart';

const _v = 1;

List<SourceBlock> _blocks() => const [
  (id: 'a', text: 'One two three.'),
  (id: 'b', text: 'Four five.'),
  (id: 'c', text: 'Six seven eight nine.'),
];

TokenizedText _text([List<SourceBlock>? blocks]) =>
    TokenizedText.from(blocks ?? _blocks(), parserVersion: _v);

void main() {
  group('construction', () {
    test('concatenates every block into one stream', () {
      final text = _text();

      expect(text.length, 9);
      expect(text.tokens.first.text, 'One');
      expect(text.tokens.last.text, 'nine.');
    });

    test('records every block that produced tokens', () {
      expect(_text().blockIds, ['a', 'b', 'c']);
    });

    test('skips blocks that produce no tokens', () {
      final text = _text(const [
        (id: 'a', text: 'Real text.'),
        (id: 'empty', text: '   '),
        (id: 'c', text: 'More text.'),
      ]);

      expect(text.blockIds, ['a', 'c']);
    });

    test('an empty input yields an empty stream', () {
      final text = _text(const []);

      expect(text.isEmpty, isTrue);
      expect(text.blockCount, 0);
      expect(text.locatorAt(0), isNull);
    });

    test('accepts a custom tokenizer', () {
      final text = TokenizedText.from(
        const [(id: 'a', text: '50 kr. and more')],
        tokenizer: Tokenizer(numericSuffixes: {'kr.'}),
        parserVersion: _v,
      );

      expect(text.tokens.first.text, '50 kr.');
    });

    test('block ids are exposed read-only', () {
      expect(() => _text().blockIds.add('x'), throwsUnsupportedError);
    });
  });

  group('token index to block', () {
    test('maps each index to its own block', () {
      final text = _text();

      expect(text.blockIndexOf(0), 0);
      expect(text.blockIndexOf(2), 0);
      expect(text.blockIndexOf(3), 1);
      expect(text.blockIndexOf(4), 1);
      expect(text.blockIndexOf(5), 2);
      expect(text.blockIndexOf(8), 2);
    });

    test('rejects out of range indexes', () {
      final text = _text();

      expect(text.blockIndexOf(-1), -1);
      expect(text.blockIndexOf(9), -1);
      expect(text.blockIndexOf(999), -1);
    });

    test('handles a single block', () {
      final text = _text(const [(id: 'only', text: 'One two three.')]);

      expect(text.blockIndexOf(0), 0);
      expect(text.blockIndexOf(2), 0);
    });

    test('binary search holds over many blocks', () {
      final blocks = [
        for (var i = 0; i < 500; i++) (id: 'b$i', text: 'Word one two.'),
      ];
      final text = _text(blocks);

      // Three tokens per block.
      expect(text.blockIndexOf(0), 0);
      expect(text.blockIndexOf(3), 1);
      expect(text.blockIndexOf(1499), 499);
      expect(text.blockIndexOf(1498), 499);
      expect(text.blockIndexOf(1497), 499);
      expect(text.blockIndexOf(1496), 498);
    });
  });

  group('locatorAt', () {
    test('reports the block id and the token offset within it', () {
      final text = _text();

      expect(
        text.locatorAt(0),
        const Locator(blockId: 'a', charOffset: 0, parserVersion: _v),
      );
      expect(
        text.locatorAt(4),
        // "five." starts at offset 5 within block b.
        const Locator(blockId: 'b', charOffset: 5, parserVersion: _v),
      );
    });

    test('offsets restart at each block', () {
      final text = _text();

      expect(text.locatorAt(3)!.charOffset, 0, reason: 'first token of b');
      expect(text.locatorAt(5)!.charOffset, 0, reason: 'first token of c');
    });

    test('carries the parser version', () {
      final text = TokenizedText.from(_blocks(), parserVersion: 7);
      expect(text.locatorAt(0)!.parserVersion, 7);
    });

    test('returns null out of range', () {
      expect(_text().locatorAt(99), isNull);
      expect(_text().locatorAt(-1), isNull);
    });
  });

  group('indexOf', () {
    test('round trips every position', () {
      final text = _text();

      for (var i = 0; i < text.length; i++) {
        expect(text.indexOf(text.locatorAt(i)!), i, reason: 'failed at $i');
      }
    });

    test('lands on the token containing an interior offset', () {
      final text = _text();

      // Offset 5 in block a is inside "two", which starts at 4.
      final index = text.indexOf(
        const Locator(blockId: 'a', charOffset: 5, parserVersion: _v),
      );
      expect(text.tokens[index!].text, 'two');
    });

    test('an offset past the block ends on its last token', () {
      final text = _text();

      final index = text.indexOf(
        const Locator(blockId: 'b', charOffset: 9999, parserVersion: _v),
      );
      expect(text.tokens[index!].text, 'five.');
    });

    test('an offset before the first token lands on it', () {
      final text = _text();

      final index = text.indexOf(
        const Locator(blockId: 'c', charOffset: 0, parserVersion: _v),
      );
      expect(text.tokens[index!].text, 'Six');
    });

    test('returns null for an unknown block', () {
      expect(
        _text().indexOf(
          const Locator(blockId: 'gone', charOffset: 0, parserVersion: _v),
        ),
        isNull,
      );
    });

    test('does not refuse a parser version mismatch', () {
      // Resuming a sentence away beats refusing to resume. Callers that need
      // a migration should compare versions themselves.
      final text = _text();
      final index = text.indexOf(
        const Locator(blockId: 'b', charOffset: 0, parserVersion: 99),
      );

      expect(index, 3);
    });
  });

  group('startOfBlock', () {
    test('finds the first token of each block', () {
      final text = _text();

      expect(text.startOfBlock('a'), 0);
      expect(text.startOfBlock('b'), 3);
      expect(text.startOfBlock('c'), 5);
    });

    test('returns null for an unknown block', () {
      expect(_text().startOfBlock('nope'), isNull);
    });
  });

  group('progress', () {
    test('runs from just above zero to one', () {
      final text = _text();

      expect(text.progressAt(0), closeTo(1 / 9, 0.001));
      expect(text.progressAt(8), 1.0);
    });

    test('clamps out of range indexes', () {
      final text = _text();

      expect(text.progressAt(999), 1.0);
      expect(text.progressAt(-5), 0.0);
    });

    test('is zero for empty text', () {
      expect(_text(const []).progressAt(0), 0);
    });
  });

  group('Locator serialization', () {
    test('round trips through JSON', () {
      const locator = Locator(
        blockId: 'abc123',
        charOffset: 456,
        parserVersion: 2,
      );

      expect(Locator.fromJson(locator.toJson()), locator);
    });

    test('tolerates missing optional fields', () {
      final locator = Locator.fromJson({'blockId': 'x'});

      expect(locator.blockId, 'x');
      expect(locator.charOffset, 0);
    });

    test('compares by value', () {
      const a = Locator(blockId: 'a', charOffset: 1, parserVersion: 1);
      const b = Locator(blockId: 'a', charOffset: 1, parserVersion: 1);
      const c = Locator(blockId: 'a', charOffset: 2, parserVersion: 1);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('a book-sized stream', () {
    late TokenizedText text;

    setUpAll(() {
      final blocks = [
        for (var i = 0; i < 1200; i++)
          (
            id: 'block$i',
            text:
                'This is a paragraph of ordinary prose, roughly the length '
                'of a sentence in a real book.',
          ),
      ];
      text = _text(blocks);
    });

    test('holds every block', () {
      expect(text.blockCount, 1200);
      expect(text.length, greaterThan(15000));
    });

    test('round trips positions throughout', () {
      for (final i in [0, 1, 500, 7500, text.length - 1]) {
        expect(text.indexOf(text.locatorAt(i)!), i, reason: 'failed at $i');
      }
    });

    test('resolves every block by id', () {
      // The id lookups moved from a linear scan to a map. What that could
      // break is which entry a lookup lands on, so this checks all 1200
      // rather than a sample.
      for (var i = 0; i < 1200; i++) {
        expect(text.startOfBlock('block$i'), isNotNull, reason: 'lost block$i');
      }
    });
  });

  group('a repeated block id', () {
    // Ids are supposed to be unique and this type cannot enforce that: it
    // takes any (id, text) pair from any caller. The scan the id map
    // replaced answered with the first match, so this pins that a map does
    // too rather than silently answering with the last.
    late TokenizedText text;

    setUp(() {
      text = _text(const [
        (id: 'dup', text: 'First block here.'),
        (id: 'other', text: 'Second block.'),
        (id: 'dup', text: 'Third block, same id as the first.'),
      ]);
    });

    test('startOfBlock answers with the first', () {
      expect(text.startOfBlock('dup'), 0);
    });

    test('indexOf resolves into the first', () {
      const locator = Locator(blockId: 'dup', charOffset: 0, parserVersion: _v);
      expect(text.indexOf(locator), 0);
    });

    test('an unknown id is still null', () {
      expect(text.startOfBlock('missing'), isNull);
    });
  });
}
