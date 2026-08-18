enum PauseAfter { none, clause, sentence, paragraph }

/// Compiled once rather than per [Token.letterCount] call.
///
/// `letterCount` is read once per token under length-scaled pacing, which is
/// the pacing the central field loss presets use, so this ran on the reading
/// path rather than only at import. The saving is small either way — 0.56µs
/// against 0.67µs per call, four times a second — but a constant pattern
/// built inside a getter is a compile nobody asked for.
final _alphanumeric = RegExp(r'[\p{L}\p{N}]', unicode: true);

class Token {
  final String text;

  final int charOffset;

  final PauseAfter pauseAfter;

  const Token({
    required this.text,
    required this.charOffset,
    this.pauseAfter = PauseAfter.none,
  });

  int get letterCount => _alphanumeric.allMatches(text).length;

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
