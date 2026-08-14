import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:epub_reader/epub_reader.dart';
import 'package:test/test.dart';

/// Builds an EPUB in memory, so every case here is a string literal rather
/// than a committed binary and runs identically on the VM and in a browser.
Uint8List _epub({
  required String manifest,
  required String spine,
  String spineAttributes = '',
  Map<String, String> files = const {},
}) {
  final archive = Archive();

  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');

  add('OEBPS/content.opf', '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Test Book</dc:title>
    <dc:language>en</dc:language>
    <dc:identifier>urn:uuid:toc</dc:identifier>
  </metadata>
  <manifest>$manifest</manifest>
  <spine$spineAttributes>$spine</spine>
</package>''');

  files.forEach(add);

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const _chapterItem =
    '<item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>';
const _chapterRef = '<itemref idref="c1"/>';

const _navItem =
    '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
    'properties="nav"/>';
const _ncxItem =
    '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>';

String _nav(String list) =>
    '''
<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml"
      xmlns:epub="http://www.idpf.org/2007/ops">
  <body>
    <nav epub:type="toc"><ol>$list</ol></nav>
  </body>
</html>''';

String _ncx(String navPoints) =>
    '''
<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>$navPoints</navMap>
</ncx>''';

/// The text of the block an entry landed on.
///
/// Asserting on text rather than on a block id keeps these tests readable and
/// keeps them from restating the hash, which `block_id_test.dart` owns.
String _landsOn(EpubBook book, TocEntry entry) =>
    book.readingOrder.firstWhere((b) => b.id == entry.blockId).text;

void main() {
  group('EPUB 3 navigation document', () {
    late EpubBook book;

    setUp(() {
      book = const EpubParser().parse(
        _epub(
          manifest: '$_chapterItem$_navItem',
          spine: _chapterRef,
          files: {
            'OEBPS/nav.xhtml': _nav(
              '<li><a href="ch1.xhtml#one">Chapter One</a></li>'
              '<li><a href="ch1.xhtml#two">Chapter Two</a>'
              '<ol><li><a href="ch1.xhtml#two-a">A Scene</a></li></ol>'
              '</li>',
            ),
            'OEBPS/ch1.xhtml':
                '<html><body>'
                '<h1 id="one">Chapter One</h1><p>Opening line.</p>'
                '<h1 id="two">Chapter Two</h1><p>Second line.</p>'
                '<h2 id="two-a">A Scene</h2><p>Third line.</p>'
                '</body></html>',
          },
        ),
      );
    });

    test('reads every entry in reading order', () {
      expect(book.toc.map((e) => e.title).toList(), [
        'Chapter One',
        'Chapter Two',
        'A Scene',
      ]);
    });

    test('nesting becomes depth', () {
      expect(book.toc.map((e) => e.depth).toList(), [0, 0, 1]);
    });

    test('each fragment resolves to its own block', () {
      // The point of the whole anchor map. All three entries live in one
      // spine document, so without fragment resolution every one of them
      // would land on the document's first block.
      expect(book.toc.map((e) => _landsOn(book, e)).toList(), [
        'Chapter One',
        'Chapter Two',
        'A Scene',
      ]);
    });

    test('the navigation document itself is not a chapter', () {
      // It is not in the spine, and the normalizer drops nav elements, so
      // nothing from it reaches the reading stream.
      expect(book.documents.map((d) => d.href), ['OEBPS/ch1.xhtml']);
    });
  });

  group('anchor placement', () {
    EpubBook parse(String body, String href) => const EpubParser().parse(
      _epub(
        manifest: '$_chapterItem$_navItem',
        spine: _chapterRef,
        files: {
          'OEBPS/nav.xhtml': _nav('<li><a href="$href">Target</a></li>'),
          'OEBPS/ch1.xhtml': '<html><body>$body</body></html>',
        },
      ),
    );

    test('an id on a wrapping container lands on its first block', () {
      // Project Gutenberg's converter puts the chapter fragment on the div
      // that wraps the chapter, not on its heading.
      final book = parse(
        '<p>Before.</p>'
            '<div id="chap"><h1>Chapter Two</h1><p>Body.</p></div>',
        'ch1.xhtml#chap',
      );

      expect(_landsOn(book, book.toc.single), 'Chapter Two');
    });

    test('an id on an empty inline anchor lands on its block', () {
      final book = parse(
        '<p>Before.</p><h1><a id="mark"></a>Chapter Two</h1>',
        'ch1.xhtml#mark',
      );

      expect(_landsOn(book, book.toc.single), 'Chapter Two');
    });

    test('an id on a block too short to keep lands on the next block', () {
      // The spacer is dropped for length, but the reader still asked to go
      // where it was.
      final book = parse(
        '<p>Before.</p><p id="mark"> </p><p>Real text.</p>',
        'ch1.xhtml#mark',
      );

      expect(_landsOn(book, book.toc.single), 'Real text.');
    });

    test('no fragment lands on the start of the document', () {
      final book = parse('<p>First.</p><p>Second.</p>', 'ch1.xhtml');

      expect(_landsOn(book, book.toc.single), 'First.');
    });

    test('an unknown fragment lands on the start of the document', () {
      // The book says the chapter is in this file. Its start is close; a
      // dropped entry is not.
      final book = parse(
        '<p>First.</p><p>Second.</p>',
        'ch1.xhtml#nothing-here',
      );

      expect(_landsOn(book, book.toc.single), 'First.');
    });
  });

  group('EPUB 2 NCX', () {
    test('is used when there is no navigation document', () {
      final book = const EpubParser().parse(
        _epub(
          manifest: '$_chapterItem$_ncxItem',
          spine: _chapterRef,
          spineAttributes: ' toc="ncx"',
          files: {
            'OEBPS/toc.ncx': _ncx(
              '<navPoint><navLabel><text>Part One</text></navLabel>'
              '<content src="ch1.xhtml#one"/>'
              '<navPoint><navLabel><text>A Section</text></navLabel>'
              '<content src="ch1.xhtml#two"/></navPoint>'
              '</navPoint>',
            ),
            'OEBPS/ch1.xhtml':
                '<html><body>'
                '<h1 id="one">Part One</h1><p>Opening.</p>'
                '<h2 id="two">A Section</h2><p>More.</p>'
                '</body></html>',
          },
        ),
      );

      expect(book.toc.map((e) => e.title).toList(), ['Part One', 'A Section']);
      expect(book.toc.map((e) => e.depth).toList(), [0, 1]);
      expect(_landsOn(book, book.toc.last), 'A Section');
    });

    test('is found even when the spine does not name it', () {
      final book = const EpubParser().parse(
        _epub(
          manifest: '$_chapterItem$_ncxItem',
          spine: _chapterRef,
          files: {
            'OEBPS/toc.ncx': _ncx(
              '<navPoint><navLabel><text>Only Chapter</text></navLabel>'
              '<content src="ch1.xhtml"/></navPoint>',
            ),
            'OEBPS/ch1.xhtml': '<html><body><p>Text.</p></body></html>',
          },
        ),
      );

      expect(book.toc.single.title, 'Only Chapter');
    });

    test('loses to a navigation document when a book carries both', () {
      // Books produced this decade ship both for compatibility. Merging them
      // would double every entry.
      final book = const EpubParser().parse(
        _epub(
          manifest: '$_chapterItem$_navItem$_ncxItem',
          spine: _chapterRef,
          spineAttributes: ' toc="ncx"',
          files: {
            'OEBPS/nav.xhtml': _nav(
              '<li><a href="ch1.xhtml">From the nav document</a></li>',
            ),
            'OEBPS/toc.ncx': _ncx(
              '<navPoint><navLabel><text>From the NCX</text></navLabel>'
              '<content src="ch1.xhtml"/></navPoint>',
            ),
            'OEBPS/ch1.xhtml': '<html><body><p>Text.</p></body></html>',
          },
        ),
      );

      expect(book.toc.single.title, 'From the nav document');
    });
  });

  group('entries that cannot be reached', () {
    test('a book with no table of contents has none', () {
      final book = const EpubParser().parse(
        _epub(
          manifest: _chapterItem,
          spine: _chapterRef,
          files: {
            'OEBPS/ch1.xhtml': '<html><body><p>Just text.</p></body></html>',
          },
        ),
      );

      // Nothing is inferred from headings to fill the gap. See ADR 0010.
      expect(book.toc, isEmpty);
    });

    test('an entry pointing at a missing document is dropped', () {
      final book = const EpubParser().parse(
        _epub(
          manifest: '$_chapterItem$_navItem',
          spine: _chapterRef,
          files: {
            'OEBPS/nav.xhtml': _nav(
              '<li><a href="ch1.xhtml">Real</a></li>'
              '<li><a href="gone.xhtml">Missing</a></li>',
            ),
            'OEBPS/ch1.xhtml': '<html><body><p>Text.</p></body></html>',
          },
        ),
      );

      // Keeping it would render a chapter that does nothing when tapped.
      expect(book.toc.map((e) => e.title).toList(), ['Real']);
    });

    test('an entry pointing outside the reading flow is dropped', () {
      final book = const EpubParser().parse(
        _epub(
          manifest:
              '$_chapterItem$_navItem'
              '<item id="c2" href="notes.xhtml" '
              'media-type="application/xhtml+xml"/>',
          spine: '$_chapterRef<itemref idref="c2" linear="no"/>',
          files: {
            'OEBPS/nav.xhtml': _nav(
              '<li><a href="ch1.xhtml">Chapter</a></li>'
              '<li><a href="notes.xhtml">Endnotes</a></li>',
            ),
            'OEBPS/ch1.xhtml': '<html><body><p>Text.</p></body></html>',
            'OEBPS/notes.xhtml': '<html><body><p>A note.</p></body></html>',
          },
        ),
      );

      // readingOrder skips non-linear documents, so an entry into one names
      // a block reading forward never reaches.
      expect(book.toc.map((e) => e.title).toList(), ['Chapter']);
    });

    test('an unreadable table of contents costs chapters, not the book', () {
      final book = const EpubParser().parse(
        _epub(
          manifest: '$_chapterItem$_navItem',
          spine: _chapterRef,
          files: {
            'OEBPS/nav.xhtml': 'not markup at all',
            'OEBPS/ch1.xhtml': '<html><body><p>Text.</p></body></html>',
          },
        ),
      );

      expect(book.toc, isEmpty);
      expect(book.readingOrder.single.text, 'Text.');
    });
  });

  group('titles', () {
    test('are flattened out of inline markup', () {
      final book = const EpubParser().parse(
        _epub(
          manifest: '$_chapterItem$_navItem',
          spine: _chapterRef,
          files: {
            'OEBPS/nav.xhtml': _nav(
              '<li><a href="ch1.xhtml">Act <b>I</b>\n  Scene 1</a></li>',
            ),
            'OEBPS/ch1.xhtml': '<html><body><p>Text.</p></body></html>',
          },
        ),
      );

      expect(book.toc.single.title, 'Act I Scene 1');
    });
  });
}
