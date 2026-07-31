import 'dart:io';

import 'package:test/test.dart';
import 'package:epub_reader/epub_reader.dart';

/// Regression test against a real book.
///
/// Every other fixture in this package is synthetic, written to match the
/// assumptions the parser already makes. This one was written by Project
/// Gutenberg's toolchain, so it is the only test that can catch those
/// assumptions being wrong.
///
/// The exact counts below are observed output, not predictions. If a change
/// to the normalizer moves them, that is a real change to stored reading
/// positions: update the numbers and bump kParserVersion together.
void main() {
  final file = File('test/fixtures/romeo-and-juliet.epub');

  group('Romeo and Juliet, Project Gutenberg ebook 1513', () {
    late EpubBook book;

    setUpAll(() {
      expect(
        file.existsSync(),
        isTrue,
        reason: 'fixture missing; see test/fixtures/README.md',
      );
      book = const EpubParser().parse(file.readAsBytesSync());
    });

    test('reads the declared metadata', () {
      expect(book.metadata.title, 'Romeo and Juliet');
      expect(book.metadata.author, 'William Shakespeare');
      expect(book.metadata.language, 'en');
      expect(book.metadata.identifier, 'http://www.gutenberg.org/1513');
    });

    test('finds the cover through the EPUB 3 properties attribute', () {
      expect(book.metadata.coverHref, 'OEBPS/5578997006791554087_cover.jpg');
    });

    test('drops the spine item that holds no text', () {
      // The spine lists ten items. The first wraps the cover image in SVG and
      // yields no blocks, so it is skipped.
      expect(book.documents.length, 9);
    });

    test('produces the expected number of blocks', () {
      expect(book.blockCount, 1154);
    });

    test('produces the expected amount of text', () {
      final chars = book.readingOrder.fold<int>(
        0,
        (sum, b) => sum + b.text.length,
      );
      expect(chars, 157920);
    });

    test('starts on the Gutenberg header', () {
      // Known limitation rather than a target: the licence front matter is
      // real text in the spine, so it reads as part of the book.
      final first = book.readingOrder.first;
      expect(first.kind, BlockKind.heading);
      expect(first.text, 'The Project Gutenberg eBook of Romeo and Juliet');
    });

    test('reaches the play itself', () {
      final headings = book.readingOrder
          .where((b) => b.kind == BlockKind.heading)
          .map((b) => b.text)
          .toList();

      expect(headings, contains('THE TRAGEDY OF ROMEO AND JULIET'));
    });

    test('every block has content', () {
      expect(book.readingOrder.every((b) => b.text.trim().isNotEmpty), isTrue);
    });

    test('no block still contains markup', () {
      final withTags = book.readingOrder
          .where((b) => b.text.contains('<'))
          .toList();

      expect(
        withTags,
        isEmpty,
        reason: 'a stray tag would be flashed at the reader as a word',
      );
    });

    test('block ids are unique across the whole book', () {
      final ids = book.readingOrder.map((b) => b.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('block ids are stable across two parses', () {
      final again = const EpubParser().parse(file.readAsBytesSync());

      expect(
        again.readingOrder.map((b) => b.id).toList(),
        equals(book.readingOrder.map((b) => b.id).toList()),
      );
    });

    test('documents keep spine order', () {
      final hrefs = book.documents.map((d) => d.href).toList();

      expect(hrefs.first, endsWith('1513-h-0.htm.xhtml'));
      expect(hrefs.last, endsWith('1513-h-8.htm.xhtml'));
    });

    test('parses in a reasonable time', () {
      // Observed around 240 ms. The ceiling is loose on purpose: this guards
      // against an accidental quadratic walk, not against normal variance.
      final stopwatch = Stopwatch()..start();
      const EpubParser().parse(file.readAsBytesSync());
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(3000));
    });
  });
}
