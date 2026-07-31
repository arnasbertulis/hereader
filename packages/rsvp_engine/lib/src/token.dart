enum PauseAfter { none, clause, sentence, paragraph }

class Token {
  final String text;

  final int charOffset;

  final PauseAfter pauseAfter;

  const Token({
    required this.text,
    required this.charOffset,
    this.pauseAfter = PauseAfter.none,
  });

  int get letterCount =>
      RegExp(r'[\p{L}\p{N}]', unicode: true).allMatches(text).length;

  @override
  String toString() => 'Token("$text" @$charOffset ${pauseAfter.name})';

  @override
  bool operator ==(Object other) =>
      other is Token &&
      other.text == text &&
      other.charOffset == charOffset &&
      other.pauseAfter == pauseAfter;

  @override
  int get hashCode => Object.hash(text, charOffset, pauseAfter);
}
