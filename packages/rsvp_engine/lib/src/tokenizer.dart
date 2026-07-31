import 'token.dart';

const _defaultAbbreviations = {
  'dr.',
  'mr.',
  'mrs.',
  'ms.',
  'prof.',
  'st.',
  'etc.',
  'e.g.',
  'i.e.',
  'vs.',
  'cf.',
  'approx.',
};

const _defaultNumericSuffixes = {
  'm.',
  'd.',
  'mėn.',
  'sav.',
  'val.',
  'min.',
  'sek.',
  'psl.',
  'nr.',
  'proc.',
  'kg',
  'g',
  'km',
  'cm',
  'mm',
  'ha',
};

const _sentenceEnders = {'.', '!', '?', '\u2026'};
const _clauseEnders = {',', ';', ':'};

final _alphanumeric = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _isWhitespace(int c) =>
    c == 0x20 ||
    c == 0x09 ||
    c == 0x0A ||
    c == 0x0D ||
    c == 0x0B ||
    c == 0x0C ||
    c == 0x2028 ||
    c == 0x2029;

PauseAfter _longer(PauseAfter a, PauseAfter b) => a.index >= b.index ? a : b;

class Tokenizer {
  final Set<String> abbreviations;
  final Set<String> numericSuffixes;

  Tokenizer({Set<String>? abbreviations, Set<String>? numericSuffixes})
    : abbreviations = abbreviations ?? _defaultAbbreviations,
      numericSuffixes = numericSuffixes ?? _defaultNumericSuffixes;

  PauseAfter _fromPunctuation(String text) {
    final lower = text.toLowerCase();
    final lastSegment = lower.split(RegExp(r'\s+')).last;
    if (abbreviations.contains(lower)) return PauseAfter.none;
    if (numericSuffixes.contains(lastSegment)) return PauseAfter.none;

    var end = text.length;
    while (end > 0 && !_alphanumeric.hasMatch(text[end - 1])) {
      end--;
    }
    final tail = text.substring(end);
    if (tail.isEmpty) return PauseAfter.none;

    for (final ch in tail.split('')) {
      if (_sentenceEnders.contains(ch)) return PauseAfter.sentence;
    }
    for (final ch in tail.split('')) {
      if (_clauseEnders.contains(ch)) return PauseAfter.clause;
    }
    return PauseAfter.none;
  }

  PauseAfter _fromFollowingWhitespace(String source, int i) {
    var newlines = 0;
    while (i < source.length && _isWhitespace(source.codeUnitAt(i))) {
      if (source.codeUnitAt(i) == 0x0A) newlines++;
      i++;
    }
    return newlines >= 2 ? PauseAfter.paragraph : PauseAfter.none;
  }

  List<Token> tokenize(String source) {
    final tokens = <Token>[];
    final n = source.length;
    var i = 0;

    while (i < n) {
      while (i < n && _isWhitespace(source.codeUnitAt(i))) {
        i++;
      }
      if (i >= n) break;

      final start = i;
      final buffer = StringBuffer();

      while (true) {
        final runStart = i;
        while (i < n && !_isWhitespace(source.codeUnitAt(i))) {
          i++;
        }
        final fragment = source.substring(runStart, i);

        if (fragment.length > 1 &&
            fragment.endsWith('-') &&
            _isLineBreakHyphen(source, i)) {
          buffer.write(fragment.substring(0, fragment.length - 1));
          while (i < n && _isWhitespace(source.codeUnitAt(i))) {
            i++;
          }
          continue;
        }

        buffer.write(fragment);
        break;
      }

      final text = buffer.toString();
      final endsInDigit =
          tokens.isNotEmpty &&
          RegExp(r'[\p{N}]$', unicode: true).hasMatch(tokens.last.text);

      if (endsInDigit && numericSuffixes.contains(text.toLowerCase())) {
        // Fold the unit into the number so "2005 m." shows as one token.
        final merged = source.substring(tokens.last.charOffset, i);
        tokens[tokens.length - 1] = Token(
          text: merged,
          charOffset: tokens.last.charOffset,
          pauseAfter: _longer(
            _fromPunctuation(merged),
            _fromFollowingWhitespace(source, i),
          ),
        );
      } else {
        tokens.add(
          Token(
            text: text,
            charOffset: start,
            pauseAfter: _longer(
              _fromPunctuation(text),
              _fromFollowingWhitespace(source, i),
            ),
          ),
        );
      }
    }

    return tokens;
  }

  bool _isLineBreakHyphen(String source, int i) {
    var newlines = 0;
    var j = i;
    while (j < source.length && _isWhitespace(source.codeUnitAt(j))) {
      if (source.codeUnitAt(j) == 0x0A) newlines++;
      j++;
    }
    return newlines == 1 && j < source.length;
  }
}
