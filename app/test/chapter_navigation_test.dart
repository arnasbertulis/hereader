import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/reader_screen.dart';
import 'package:epub_reader/epub_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'test_database.dart';

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

/// Forty blocks, each its own chapter, which is more than fits a panel.
(TokenizedText, List<Chapter>) _longBook() {
  final blocks = [
    for (var i = 0; i < 40; i++) (id: 'c$i', text: 'Word$i more words here.'),
  ];

  final text = TokenizedText.from(blocks, parserVersion: 1);

  return (
    text,
    [
      for (var i = 0; i < 40; i++)
        Chapter(
          title: 'Chapter $i',
          depth: 0,
          tokenIndex: text.startOfBlock('c$i')!,
        ),
    ],
  );
}

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

    setUp(() => database = AppDatabase(testExecutor()));
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

    testWidgets('opening the panel reveals the chapter being read', (
      tester,
    ) async {
      final (text, chapters) = _longBook();

      await tester.pumpWidget(
        reader(
          LibraryBook(
            id: 'b',
            title: 'A Book',
            text: text,
            chapters: chapters,
            contentStartIndex: chapters[30].tokenIndex,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Chapters'));
      await tester.pumpAndSettle();

      final height =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;

      // On screen, and roughly centred rather than merely built: a non-lazy
      // list builds every tile, so finding the text proves nothing about
      // where the panel is scrolled to.
      final current = tester.getCenter(find.text('Chapter 30')).dy;
      expect(current, greaterThan(0));
      expect(current, lessThan(height));

      // The control: the first chapter is where an unscrolled panel would be
      // sitting, and a lazy list does not build a tile it has scrolled past,
      // so its absence is what says a scroll happened at all.
      expect(find.text('Chapter 0'), findsNothing);
    });

    testWidgets('it reveals the new chapter on a second open, not the first', (
      tester,
    ) async {
      final (text, chapters) = _longBook();

      await tester.pumpWidget(
        reader(
          LibraryBook(
            id: 'b',
            title: 'A Book',
            text: text,
            chapters: chapters,
            contentStartIndex: chapters[30].tokenIndex,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Chapters'));
      await tester.pumpAndSettle();

      // Near the centred current chapter, so it is on screen to be tapped.
      await tester.tap(find.text('Chapter 32'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Chapters'));
      await tester.pumpAndSettle();

      final height =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final current = tester.getCenter(find.text('Chapter 32')).dy;

      expect(current, greaterThan(0));
      expect(current, lessThan(height));
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

    testWidgets(
      'resuming after a chapter jump does not rewind by rewindWords',
      (tester) async {
        // `_goToChapter` used to reach its target through `seekToIndex`,
        // which carries none of `stopAt`'s resume-rewind suppression: the
        // next play would step back and land in the chapter just left.
        final text = _text();

        await tester.pumpWidget(
          reader(
            LibraryBook(
              id: 'b',
              title: 'A Book',
              text: text,
              chapters: [
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
        await tester.tap(find.text('Chapter Two'));
        await tester.pumpAndSettle();

        expect(find.text('Delta'), findsOneWidget);

        await tester.tap(find.byKey(readerPlayButtonKey));
        await tester.pump();

        expect(find.text('Delta'), findsOneWidget);
      },
    );
  });

  group('the front matter offer', () {
    late AppDatabase database;
    late LibraryRepository repository;

    setUp(() {
      database = AppDatabase(testExecutor());
      repository = LibraryRepository(database);
    });
    tearDown(() => database.close());

    Widget reader(LibraryBook book) => MaterialApp(
      home: ReaderScreen(
        book: book,
        repository: repository,
        issueStamp: _stamp,
        onSave: (_) async {},
      ),
    );

    testWidgets(
      'accepting it under elicited pacing keeps advancing rather than pausing',
      (tester) async {
        // `_goToFrontMatter` used to reach index 0 through `seekToIndex`,
        // which forces the session to `paused` whenever it was not already
        // `playing` — collapsing `awaitingAdvance`, elicited pacing's
        // active-reading state, into a stop the reader never asked for. The
        // rewind-on-resume symptom `_goToChapter`'s test catches does not
        // show here: it clamps to nothing at index 0.
        await repository.setActiveProfile(
          Presets.centralFieldLoss.id,
          hlc: await _stamp(),
        );

        final text = _text();

        await tester.pumpWidget(
          reader(
            LibraryBook(
              id: 'b',
              title: 'A Book',
              text: text,
              contentStartIndex: text.startOfBlock('one')!,
              contentStartReason: ContentStartReason.boilerplateHeuristic,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(readerPlayButtonKey));
        await tester.pumpAndSettle();

        expect(find.text('Alpha'), findsOneWidget);
        expect(find.byTooltip('Stop advancing'), findsOneWidget);

        await tester.tap(find.text('Start at the beginning'));
        await tester.pumpAndSettle();

        expect(find.text('Licence'), findsOneWidget);
        expect(find.byTooltip('Stop advancing'), findsOneWidget);
      },
    );
  });

  /// The walk the panel's highlight and the saved hint both go through.
  ///
  /// Lifted out of `ReaderScreen` when the hint started reading it: the panel
  /// and the tile answer the same question, and two functions computing one
  /// figure disagree eventually rather than maybe.
  group('chapter spans', () {
    const chapters = [
      Chapter(title: 'Act I', depth: 0, tokenIndex: 10),
      Chapter(title: 'Scene I', depth: 1, tokenIndex: 10),
      Chapter(title: 'Scene II', depth: 1, tokenIndex: 40),
      Chapter(title: 'Act II', depth: 0, tokenIndex: 90),
    ];

    test('front matter is in no chapter', () {
      expect(chapterIndexAt(chapters, 0), -1);
      expect(chapterIndexAt(chapters, 9), -1);
    });

    test('a book with no contents is in no chapter', () {
      expect(chapterIndexAt(const [], 500), -1);
    });

    test('the last entry of a shared start wins', () {
      // Act I and Scene I resolve to the same token, which is ordinary: a
      // part and its first chapter routinely do. The reader is in the
      // narrower one, and that is the one worth naming on a tile.
      expect(chapterIndexAt(chapters, 10), 1);
      expect(chapters[chapterIndexAt(chapters, 39)].title, 'Scene I');
    });

    test('the last chapter holds everything after it', () {
      expect(chapterIndexAt(chapters, 90), 3);
      expect(chapterIndexAt(chapters, 100000), 3);
    });

    test('a chapter ends where the next one starts', () {
      expect(chapterEndAt(chapters, 2, 500), 90);
    });

    test('a shared start does not make an empty chapter', () {
      // Taking `at + 1` blindly would end Act I at token 10, the token it
      // begins on, and report a chapter with nothing in it.
      expect(chapterEndAt(chapters, 0, 500), 40);
      expect(chapterEndAt(chapters, 1, 500), 40);
    });

    test('the last chapter ends at the end of the book', () {
      expect(chapterEndAt(chapters, 3, 500), 500);
    });

    test('no chapter ends at the end of the book', () {
      // -1 is what chapterIndexAt gives in front matter. Defined rather than
      // thrown: a caller with no chapter draws no chapter-scoped figure, so
      // this shape never reaches a screen, and the arithmetic behind a tile
      // should have no case that can crash it.
      expect(chapterEndAt(chapters, -1, 500), 500);
      expect(chapterEndAt(const [], 0, 500), 500);
    });
  });
}
