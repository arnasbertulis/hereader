import 'package:drift/native.dart';
import 'package:epub_reader/epub_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/reader_screen.dart';

Future<String> _stamp() async => '0000000000001-00000-test';

/// Three blocks: front matter and two chapters.
TokenizedText _text() => TokenizedText.from(const [
  (id: 'front', text: 'Licence notice here.'),
  (id: 'one', text: 'Alpha beta gamma.'),
  (id: 'two', text: 'Delta epsilon zeta.'),
], parserVersion: 1);

Block _block(String id, String href, int index, String text) => Block(
  id: id,
  href: href,
  index: index,
  kind: BlockKind.paragraph,
  text: text,
);

void main() {
  group('chaptersOf', () {
    test('resolves each entry to the first token of its block', () {
      final text = _text();

      final book = EpubBook(
        metadata: const EpubMetadata(title: 'A Book'),
        documents: [
          EpubDocument(
            href: 'ch.xhtml',
            blocks: [
              _block('front', 'ch.xhtml', 0, 'Licence notice here.'),
              _block('one', 'ch.xhtml', 1, 'Alpha beta gamma.'),
              _block('two', 'ch.xhtml', 2, 'Delta epsilon zeta.'),
            ],
          ),
        ],
        toc: const [
          TocEntry(title: 'Chapter One', blockId: 'one', depth: 0),
          TocEntry(title: 'A Scene', blockId: 'two', depth: 1),
        ],
      );

      final chapters = chaptersOf(book, text);

      expect(chapters.map((c) => c.title).toList(), ['Chapter One', 'A Scene']);
      expect(chapters.map((c) => c.depth).toList(), [0, 1]);
      expect(chapters[0].tokenIndex, text.startOfBlock('one'));
      expect(chapters[1].tokenIndex, text.startOfBlock('two'));

      // Not merely non-zero: the chapter has to start where its own text
      // does, not where the book does.
      expect(text.tokens[chapters[1].tokenIndex].text, 'Delta');
    });

    test('an entry whose block produced no tokens walks forward', () {
      // TokenizedText.from skips blocks that tokenize to nothing, so
      // startOfBlock returns null for a block that genuinely exists.
      final text = TokenizedText.from(const [
        (id: 'one', text: 'Alpha beta.'),
        (id: 'empty', text: ''),
        (id: 'two', text: 'Delta epsilon.'),
      ], parserVersion: 1);

      final book = EpubBook(
        metadata: const EpubMetadata(title: 'A Book'),
        documents: [
          EpubDocument(
            href: 'ch.xhtml',
            blocks: [
              _block('one', 'ch.xhtml', 0, 'Alpha beta.'),
              _block('empty', 'ch.xhtml', 1, ''),
              _block('two', 'ch.xhtml', 2, 'Delta epsilon.'),
            ],
          ),
        ],
        toc: const [
          TocEntry(title: 'Silent Start', blockId: 'empty', depth: 0),
        ],
      );

      final chapters = chaptersOf(book, text);

      // Landing a line late is invisible; dropping the chapter is not.
      expect(chapters.single.tokenIndex, text.startOfBlock('two'));
    });

    test('an entry outside the reading order is dropped', () {
      final text = _text();

      final book = EpubBook(
        metadata: const EpubMetadata(title: 'A Book'),
        documents: [
          EpubDocument(
            href: 'ch.xhtml',
            blocks: [_block('one', 'ch.xhtml', 0, 'Alpha beta gamma.')],
          ),
        ],
        toc: const [
          TocEntry(title: 'Real', blockId: 'one', depth: 0),
          TocEntry(title: 'Nowhere', blockId: 'absent', depth: 0),
        ],
      );

      expect(chaptersOf(book, text).map((c) => c.title).toList(), ['Real']);
    });

    test('a book with no table of contents has no chapters', () {
      final book = EpubBook(
        metadata: const EpubMetadata(title: 'A Book'),
        documents: [
          EpubDocument(
            href: 'ch.xhtml',
            blocks: [_block('one', 'ch.xhtml', 0, 'Alpha beta gamma.')],
          ),
        ],
      );

      expect(chaptersOf(book, _text()), isEmpty);
    });
  });

  group('the chapter panel', () {
    late AppDatabase database;

    setUp(() => database = AppDatabase(NativeDatabase.memory()));
    tearDown(() => database.close());

    Widget reader(LibraryBook book) => MaterialApp(
      home: ReaderScreen(
        book: book,
        repository: LibraryRepository(database),
        issueStamp: _stamp,
        onSave: (_) async {},
      ),
    );

    testWidgets('choosing a chapter moves the reader to its first word', (
      tester,
    ) async {
      final text = _text();

      await tester.pumpWidget(
        reader(
          LibraryBook(
            id: 'b',
            title: 'A Book',
            text: text,
            chapters: [
              Chapter(
                title: 'Chapter One',
                depth: 0,
                tokenIndex: text.startOfBlock('one')!,
              ),
              Chapter(
                title: 'Chapter Two',
                depth: 0,
                tokenIndex: text.startOfBlock('two')!,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Chapters'));
      await tester.pumpAndSettle();

      expect(find.text('Chapter One'), findsOneWidget);
      expect(find.text('Chapter Two'), findsOneWidget);

      await tester.tap(find.text('Chapter Two'));
      await tester.pumpAndSettle();

      // The surface is showing the chapter's first token, paused, rather
      // than having resumed playback somewhere the reader has not looked.
      expect(find.text('Delta'), findsOneWidget);
    });

    testWidgets('a book that declares no chapters offers no button', (
      tester,
    ) async {
      await tester.pumpWidget(
        reader(LibraryBook(id: 'b', title: 'A Book', text: _text())),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Chapters'), findsNothing);
    });
  });
}
