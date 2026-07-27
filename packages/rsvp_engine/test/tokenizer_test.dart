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
}