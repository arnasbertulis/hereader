import 'package:epub_reader/epub_reader.dart';
import 'package:test/test.dart';

/// Direct coverage of the block-id hash, on every platform the package
/// compiles for.
///
/// This existed nowhere before. `front_matter_test.dart` calls
/// [Block.makeId] but only to obtain distinct ids, and the golden test
/// asserts counts and text rather than identifiers, so nothing anywhere
/// checked what the function actually returns.
///
/// That mattered because the ids are load-bearing: a reading position is
/// `{blockId, charOffset, parserVersion}` per ADR 0002, so a hash that
/// changes value silently moves every saved position in every book, on
/// every device that syncs.
///
/// The expected values below are literals rather than computed, which is
/// the point. Recomputing the hash inside the test would pass against a
/// wrong implementation as readily as a right one. If a change here fails,
/// treat it as a change to stored positions and bump `kParserVersion`
/// deliberately — the same rule the golden test's counts follow.
///
/// Under `dart test -p chrome` this runs through dart2js, which is the
/// reason the file is worth having. The 64-bit hash this replaced failed to
/// compile for web; a subtler error in the shift decomposition below would
/// compile cleanly and simply produce different numbers, which only an
/// asserted value catches.
void main() {
  group('Block.makeId', () {
    test('hashes to known values', () {
      expect(Block.makeId('a.xhtml', 0), 'bdbba9b4');
      expect(Block.makeId('a.xhtml', 1), 'bebbab47');
      expect(Block.makeId('OEBPS/chapter1.xhtml', 12), 'd79a9114');
    });

    test('stays inside 32 bits', () {
      // The mask is what keeps this exact under dart2js: a JS number holds
      // integers exactly only below 2^53, and the multiply step this
      // decomposes into shifts would exceed that without it.
      for (var i = 0; i < 500; i++) {
        final id = int.parse(Block.makeId('OEBPS/text$i.xhtml', i), radix: 16);
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThanOrEqualTo(0xFFFFFFFF));
      }
    });

    test('separates href from index', () {
      // '#' is the separator, so a href ending in a digit must not collide
      // with a different href and index that concatenate the same way.
      expect(Block.makeId('a1.xhtml', 2), isNot(Block.makeId('a.xhtml', 12)));
    });

    test('is stable across calls', () {
      expect(Block.makeId('a.xhtml', 7), Block.makeId('a.xhtml', 7));
    });
  });
}
