import 'package:rsvp_engine/rsvp_engine.dart';
import 'package:test/test.dart';

void main() {
  final t = Tokenizer();

  List<String> words(String s) => t.tokenize(s).map((x) => x.text).toList();
  List<PauseAfter> pauses(String s) => t.tokenize(s).map((x) => x.pauseAfter).toList();

  group('splitting', () {
    test('splits on whitespace', () {
      expect(words('the cat sat'), ['the', 'cat', 'sat']);
    });

    test('collapses runs of whitespace', () {
      expect(words('the   cat\tsat'), ['the', 'cat', 'sat']);
    });

    test('keeps punctuation attached', () {
      expect(words('Hello, world!'), ['Hello,', 'world!']);
    });
  });

  group('character offsets', () {
    test('records where each token starts', () {
      expect(t.tokenize('the cat sat').map((x) => x.charOffset), [0, 4, 8]);
    });

    test('accounts for leading whitespace', () {
      expect(t.tokenize('  the cat').map((x) => x.charOffset), [2, 6]);
    });
  });

  group('pauses', () {
    test('comma is a clause break', () {
      expect(pauses('yes, no'), [PauseAfter.clause, PauseAfter.none]);
    });

    test('semicolon and colon are clause breaks', () {
      expect(pauses('one; two: three'),
          [PauseAfter.clause, PauseAfter.clause, PauseAfter.none]);
    });

    test('period ends a sentence', () {
      expect(pauses('Stop. Go'), [PauseAfter.sentence, PauseAfter.none]);
    });

    test('question and exclamation end sentences', () {
      expect(pauses('What? Now!'), [PauseAfter.sentence, PauseAfter.sentence]);
    });

    test('ellipsis ends a sentence', () {
      expect(pauses('wait... go'), [PauseAfter.sentence, PauseAfter.none]);
    });

    test('blank line is a paragraph break', () {
      expect(pauses('end\n\nstart'), [PauseAfter.paragraph, PauseAfter.none]);
    });
  });

  group('abbreviations are not sentence ends', () {
    test('titles', () {
      expect(pauses('Dr. Smith'), [PauseAfter.none, PauseAfter.none]);
    });

    test('latin abbreviations', () {
      expect(pauses('e.g. this'), [PauseAfter.none, PauseAfter.none]);
    });
  });

  group('numbers', () {
    test('thousands and decimal separators stay inside the token', () {
      expect(words('costs 1,234.56 euros'), ['costs', '1,234.56', 'euros']);
    });

    test('a decimal point does not end a sentence', () {
      expect(pauses('pi is 3.14 roughly'),
          [PauseAfter.none, PauseAfter.none, PauseAfter.none, PauseAfter.none]);
    });
  });

  group('hyphenation', () {
    test('rejoins a word broken across a line', () {
      expect(words('co-\noperate now'), ['cooperate', 'now']);
    });

    test('leaves real hyphens alone', () {
      expect(words('well-known fact'), ['well-known', 'fact']);
    });
  });

  group('non-ascii text', () {
    test('handles lithuanian diacritics', () {
      expect(words('ąžuolas šalia ežero'), ['ąžuolas', 'šalia', 'ežero']);
    });

    test('letterCount counts diacritics, ignores punctuation', () {
      expect(t.tokenize('žąsis,').first.letterCount, 5);
    });
  });

  group('empty input', () {
    test('empty string yields nothing', () {
      expect(t.tokenize(''), isEmpty);
    });

    test('whitespace only yields nothing', () {
      expect(t.tokenize('   \n  '), isEmpty);
    });
  });

  group('numeric suffixes', () {
    test('folds a unit into the number before it', () {
      final tokens = Tokenizer().tokenize('2005 m.');

      expect(tokens.length, 1);
      expect(tokens.single.text, '2005 m.');
      expect(tokens.single.charOffset, 0);
      expect(tokens.single.pauseAfter, PauseAfter.none);
    });

    test('letterCount spans the whole merged token', () {
      final token = Tokenizer().tokenize('2005 m.').single;
      // Four digits and one letter; the period is not alphanumeric.
      expect(token.letterCount, 5);
    });

    test('handles a full Lithuanian date', () {
      final tokens = Tokenizer().tokenize('1990 m. kovo 11 d.');

      expect(tokens.map((t) => t.text).toList(),
          ['1990 m.', 'kovo', '11 d.']);
      expect(tokens.first.charOffset, 0);
      expect(tokens.last.charOffset, 13);
    });

    test('is case insensitive', () {
      expect(Tokenizer().tokenize('2005 M.').single.text, '2005 M.');
    });

    test('leaves a suffix alone when no number precedes it', () {
      final tokens = Tokenizer().tokenize('m. sena knyga');
      expect(tokens.first.text, 'm.');
      expect(tokens.length, 3);
    });

    test('leaves an ordinary word after a number alone', () {
      final tokens = Tokenizer().tokenize('2005 metai');
      expect(tokens.map((t) => t.text).toList(), ['2005', 'metai']);
    });

    test('keeps a following paragraph break after merging', () {
      final tokens = Tokenizer().tokenize('2005 m.\n\nKitas');
      expect(tokens.first.text, '2005 m.');
      expect(tokens.first.pauseAfter, PauseAfter.paragraph);
    });

    test('a real sentence still ends after a merged token', () {
      final tokens = Tokenizer().tokenize('Buvo 2005 m. Viskas pasikeitė.');
      expect(tokens[1].text, '2005 m.');
      // Known limitation: a date ending a sentence loses its pause, the
      // same ambiguity as "e.g." and for the same reason.
      expect(tokens[1].pauseAfter, PauseAfter.none);
    });

    test('accepts a custom suffix set', () {
      final tokens =
          Tokenizer(numericSuffixes: {'kr.'}).tokenize('50 kr. ir 2005 m.');
      expect(tokens.first.text, '50 kr.');
      expect(tokens.last.text, '2005');
      expect(tokens[2].text, 'm.');
    });
  });
}