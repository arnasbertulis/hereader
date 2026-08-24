import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:epub_reader/epub_reader.dart';
import 'package:test/test.dart';

Uint8List _epub({
  String opfPath = 'OEBPS/content.opf',
  String? container,
  required String opf,
  Map<String, String> documents = const {},
}) {
  final archive = Archive();

  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add(
    'META-INF/container.xml',
    container ??
        '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="$opfPath" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''',
  );
  add(opfPath, opf);
  documents.forEach(add);

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _opf({
  String title = 'Test Book',
  String author = 'A Writer',
  String language = 'lt',
  String manifest = '',
  String spine = '',
}) =>
    '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
    <dc:creator>$author</dc:creator>
    <dc:language>$language</dc:language>
    <dc:identifier>urn:uuid:1234</dc:identifier>
  </metadata>
  <manifest>$manifest</manifest>
  <spine>$spine</spine>
</package>''';

/// A zip of [count] one-byte entries, for the entry-count guard.
///
/// Not an EPUB: it carries no `META-INF/container.xml`, so an archive that
/// gets past the guard fails a few lines later for that reason instead.
/// Which of the two happened is the assertion, so the tests below match on
/// the message rather than on `EpubException` alone.
Uint8List _entries(int count) {
  final archive = Archive();
  for (var i = 0; i < count; i++) {
    archive.addFile(ArchiveFile('f$i', 1, [0]));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// A zip with one entry declaring [bytes] uncompressed, holding one byte.
///
/// The central directory's declared size is what the guard reads, and
/// `ZipEncoder` writes the declared value through rather than recomputing
/// it from the content — which is the same gap the root README records as
/// a known limitation.
Uint8List _declaringSize(int bytes) {
  final archive = Archive()..addFile(ArchiveFile('big.bin', bytes, [0]));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Every failure in this parser is an `EpubException`, so the type alone
/// says nothing about which check fired.
Matcher _throwsEpubMessage(String fragment) => throwsA(
  isA<EpubException>().having((e) => e.message, 'message', contains(fragment)),
);

void main() {
  group('a minimal book', () {
    late EpubBook book;

    setUp(() {
      book = const EpubParser().parse(
        _epub(
          opf: _opf(
            manifest:
                '<item id="c1" href="ch1.xhtml" '
                'media-type="application/xhtml+xml"/>',
            spine: '<itemref idref="c1"/>',
          ),
          documents: {
            'OEBPS/ch1.xhtml':
                '<html><body><h1>One</h1><p>First line.</p></body></html>',
          },
        ),
      );
    });

    test('reads metadata', () {
      expect(book.metadata.title, 'Test Book');
      expect(book.metadata.author, 'A Writer');
      expect(book.metadata.language, 'lt');
    });

    test('reads the spine into documents', () {
      expect(book.documents.length, 1);
      expect(book.documents.single.href, 'OEBPS/ch1.xhtml');
    });

    test('normalizes each document into blocks', () {
      expect(book.readingOrder.map((b) => b.text).toList(), [
        'One',
        'First line.',
      ]);
    });
  });

  group('paths', () {
    test('resolves hrefs relative to the package document', () {
      final book = const EpubParser().parse(
        _epub(
          opfPath: 'OEBPS/pkg/content.opf',
          opf: _opf(
            manifest:
                '<item id="c1" href="../Text/ch1.xhtml" '
                'media-type="application/xhtml+xml"/>',
            spine: '<itemref idref="c1"/>',
          ),
          documents: {
            'OEBPS/Text/ch1.xhtml': '<html><body><p>Up one.</p></body></html>',
          },
        ),
      );

      expect(book.documents.single.href, 'OEBPS/Text/ch1.xhtml');
      expect(book.readingOrder.single.text, 'Up one.');
    });

    test('decodes percent-encoded hrefs', () {
      final book = const EpubParser().parse(
        _epub(
          opf: _opf(
            manifest:
                '<item id="c1" href="chapter%201.xhtml" '
                'media-type="application/xhtml+xml"/>',
            spine: '<itemref idref="c1"/>',
          ),
          documents: {
            'OEBPS/chapter 1.xhtml': '<html><body><p>Spaced.</p></body></html>',
          },
        ),
      );

      expect(book.readingOrder.single.text, 'Spaced.');
    });
  });

  group('spine handling', () {
    test('keeps documents in spine order, not manifest order', () {
      final book = const EpubParser().parse(
        _epub(
          opf: _opf(
            manifest:
                '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>'
                '<item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>',
            spine: '<itemref idref="b"/><itemref idref="a"/>',
          ),
          documents: {
            'OEBPS/a.xhtml': '<html><body><p>Alpha.</p></body></html>',
            'OEBPS/b.xhtml': '<html><body><p>Beta.</p></body></html>',
          },
        ),
      );

      expect(book.readingOrder.map((b) => b.text).toList(), [
        'Beta.',
        'Alpha.',
      ]);
    });

    test('excludes non-linear items from the reading order', () {
      final book = const EpubParser().parse(
        _epub(
          opf: _opf(
            manifest:
                '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>'
                '<item id="n" href="n.xhtml" media-type="application/xhtml+xml"/>',
            spine: '<itemref idref="a"/><itemref idref="n" linear="no"/>',
          ),
          documents: {
            'OEBPS/a.xhtml': '<html><body><p>Main text.</p></body></html>',
            'OEBPS/n.xhtml': '<html><body><p>A footnote.</p></body></html>',
          },
        ),
      );

      expect(book.documents.length, 2, reason: 'both are parsed');
      expect(book.readingOrder.map((b) => b.text).toList(), ['Main text.']);
    });

    test('skips a spine item whose file is missing', () {
      final book = const EpubParser().parse(
        _epub(
          opf: _opf(
            manifest:
                '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>'
                '<item id="gone" href="gone.xhtml" media-type="application/xhtml+xml"/>',
            spine: '<itemref idref="gone"/><itemref idref="a"/>',
          ),
          documents: {
            'OEBPS/a.xhtml': '<html><body><p>Survived.</p></body></html>',
          },
        ),
      );

      expect(book.readingOrder.single.text, 'Survived.');
    });

    test('skips non-markup spine items', () {
      final book = const EpubParser().parse(
        _epub(
          opf: _opf(
            manifest:
                '<item id="img" href="cover.svg" media-type="image/svg+xml"/>'
                '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>',
            spine: '<itemref idref="img"/><itemref idref="a"/>',
          ),
          documents: {
            'OEBPS/a.xhtml': '<html><body><p>Text.</p></body></html>',
          },
        ),
      );

      expect(book.documents.length, 1);
    });
  });

  group('covers', () {
    test('finds an EPUB 3 cover', () {
      final book = const EpubParser().parse(
        _epub(
          opf: _opf(
            manifest:
                '<item id="cov" href="images/cover.jpg" media-type="image/jpeg" '
                'properties="cover-image"/>'
                '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>',
            spine: '<itemref idref="a"/>',
          ),
          documents: {
            'OEBPS/a.xhtml': '<html><body><p>Text.</p></body></html>',
          },
        ),
      );

      expect(book.metadata.coverHref, 'OEBPS/images/cover.jpg');
    });

    test('finds an EPUB 2 cover declared in metadata', () {
      final book = const EpubParser().parse(
        _epub(
          opf: '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Old Book</dc:title>
    <meta name="cover" content="cov"/>
  </metadata>
  <manifest>
    <item id="cov" href="images/front.jpg" media-type="image/jpeg"/>
    <item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="a"/></spine>
</package>''',
          documents: {
            'OEBPS/a.xhtml': '<html><body><p>Text.</p></body></html>',
          },
        ),
      );

      expect(book.metadata.title, 'Old Book');
      expect(book.metadata.coverHref, 'OEBPS/images/front.jpg');
    });

    test('reports no cover when the book declares none', () {
      final book = const EpubParser().parse(
        _epub(
          opf: _opf(
            manifest:
                '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>',
            spine: '<itemref idref="a"/>',
          ),
          documents: {
            'OEBPS/a.xhtml': '<html><body><p>Text.</p></body></html>',
          },
        ),
      );

      expect(book.metadata.coverHref, isNull);
    });
  });

  group('block ids across a whole book', () {
    test('are unique across documents', () {
      final book = const EpubParser().parse(
        _epub(
          opf: _opf(
            manifest:
                '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>'
                '<item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>',
            spine: '<itemref idref="a"/><itemref idref="b"/>',
          ),
          documents: {
            // Identical content in two files: ids must still differ, because
            // they are namespaced by href.
            'OEBPS/a.xhtml':
                '<html><body><p>Same.</p><p>Same.</p></body></html>',
            'OEBPS/b.xhtml':
                '<html><body><p>Same.</p><p>Same.</p></body></html>',
          },
        ),
      );

      final ids = book.readingOrder.map((b) => b.id).toList();
      expect(ids.length, 4);
      expect(ids.toSet().length, 4);
    });

    test('block indexes restart per document', () {
      final book = const EpubParser().parse(
        _epub(
          opf: _opf(
            manifest:
                '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>'
                '<item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>',
            spine: '<itemref idref="a"/><itemref idref="b"/>',
          ),
          documents: {
            'OEBPS/a.xhtml': '<html><body><p>One.</p><p>Two.</p></body></html>',
            'OEBPS/b.xhtml': '<html><body><p>Three.</p></body></html>',
          },
        ),
      );

      expect(book.documents[0].blocks.map((b) => b.index).toList(), [0, 1]);
      expect(book.documents[1].blocks.single.index, 0);
    });
  });

  group('broken input', () {
    test('rejects a file that is not a zip', () {
      expect(
        () => const EpubParser().parse(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<EpubException>()),
      );
    });

    test('rejects a zip with no container', () {
      final archive = Archive()
        ..addFile(ArchiveFile('random.txt', 3, utf8.encode('abc')));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

      expect(
        () => const EpubParser().parse(bytes),
        throwsA(isA<EpubException>()),
      );
    });

    test('rejects an archive with too many entries', () {
      expect(
        () => const EpubParser().parse(_entries(10001)),
        _throwsEpubMessage('too many entries'),
      );
    });

    test('accepts an archive at exactly the entry cap', () {
      // Pins the cap's boundary, and is the test that would fail if the
      // guard were dropped: without it, both cases reach the same
      // missing-container error and no assertion could tell them apart.
      expect(
        () => const EpubParser().parse(_entries(10000)),
        _throwsEpubMessage('META-INF/container.xml'),
      );
    });

    test(
      'rejects an archive whose declared uncompressed size is too large',
      () {
        expect(
          () => const EpubParser().parse(_declaringSize(512 * 1024 * 1024 + 1)),
          _throwsEpubMessage('too much uncompressed content'),
        );
      },
    );

    test('accepts an archive at exactly the declared-size cap', () {
      expect(
        () => const EpubParser().parse(_declaringSize(512 * 1024 * 1024)),
        _throwsEpubMessage('META-INF/container.xml'),
      );
    });

    test('rejects a book with no readable documents', () {
      expect(
        () => const EpubParser().parse(
          _epub(
            opf: _opf(
              manifest:
                  '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>',
              spine: '<itemref idref="a"/>',
            ),
          ),
        ),
        throwsA(isA<EpubException>()),
      );
    });

    test('reports malformed package XML as an EpubException', () {
      expect(
        () => const EpubParser().parse(
          _epub(
            opf: '<?xml version="1.0"?><package><manifest>',
            documents: {
              'OEBPS/a.xhtml': '<html><body><p>Text.</p></body></html>',
            },
          ),
        ),
        throwsA(isA<EpubException>()),
      );
    });

    test('reports a malformed container as an EpubException', () {
      expect(
        () => const EpubParser().parse(
          _epub(container: '<container><rootfiles>', opf: _opf()),
        ),
        throwsA(isA<EpubException>()),
      );
    });

    test('rejects a document that contains only unreadable markup', () {
      expect(
        () => const EpubParser().parse(
          _epub(
            opf: _opf(
              manifest:
                  '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>',
              spine: '<itemref idref="a"/>',
            ),
            documents: {
              'OEBPS/a.xhtml':
                  '<html><body><table><tr><td>x</td></tr></table></body></html>',
            },
          ),
        ),
        throwsA(isA<EpubException>()),
      );
    });

    test('falls back to a placeholder title', () {
      final book = const EpubParser().parse(
        _epub(
          opf: '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"/>
  <manifest><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/></manifest>
  <spine><itemref idref="a"/></spine>
</package>''',
          documents: {
            'OEBPS/a.xhtml': '<html><body><p>Text.</p></body></html>',
          },
        ),
      );

      expect(book.metadata.title, 'Untitled');
    });
  });
}
