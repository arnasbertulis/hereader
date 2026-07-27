import 'token.dart';

const _defaultAbbreviations = {
  'dr.', 'mr.', 'mrs.', 'ms.', 'prof.', 'st.',
  'etc.', 'e.g.', 'i.e.', 'vs.', 'cf.', 'approx.',
};

const _sentenceEnders = {'.', '!', '?', '\u2026'};
const _clauseEnders = {',', ';', ':'};

final _alphanumeric = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _isWhitespace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D ||
    c == 0x0B || c == 0x0C || c == 0x2028 || c == 0x2029;

PauseAfter _longer(PauseAfter a, PauseAfter b) => a.index >= b.index ? a : b;

class Tokenizer {
  final Set<String> abbreviations;

  Tokenizer({Set<String>? abbreviations})
      : abbreviations = abbreviations ?? _defaultAbbreviations;

  PauseAfter _fromPunctuation(String text) {
    if (abbreviations.contains(text.toLowerCase())) return PauseAfter.none;

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

      tokens.add(Token(
        text: buffer.toString(),
        charOffset: start,
        pauseAfter: _longer(
          _fromPunctuation(buffer.toString()),
          _fromFollowingWhitespace(source, i),
        ),
      ));
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

