import 'package:app/catalogue/language_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps a two-letter ISO 639-1 code to its display name', () {
    expect(languageDisplayName('en'), 'English');
  });

  test('maps a three-letter historical code to its display name', () {
    expect(languageDisplayName('ang'), 'Old English');
  });

  test('falls back to the raw code when unmapped', () {
    expect(languageDisplayName('xx-unknown'), 'xx-unknown');
  });
}
