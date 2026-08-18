import 'package:app/data/library_repository.dart';
import 'package:app/reading/book_progress.dart';
import 'package:app/reading/reading_display.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// 250 words a minute, so a count of words divides into minutes by four.
const _steady = PacingConfig(kind: PacingModelKind.constant, baseWpm: 250);

const _elicited = PacingConfig(
  kind: PacingModelKind.elicited,
  baseWpm: 250,
);

BookSummary _book({
  int wordCount = 10000,
  int? tokenIndex,
  String? chapterTitle,
  int? chapterEndIndex,
}) => BookSummary(
  id: 'book-1',
  title: 'Romeo and Juliet',
  author: 'William Shakespeare',
  wordCount: wordCount,
  importedAt: DateTime.utc(2026, 1, 1),
  sourceFormat: 'epub',
  position: const Locator(
    blockId: 'block-7',
    charOffset: 0,
    parserVersion: 1,
  ),
  tokenIndex: tokenIndex,
  chapterTitle: chapterTitle,
  chapterEndIndex: chapterEndIndex,
);

void main() {
  group('tokensLeft', () {
    test('the book scope counts to the end of the book', () {
      final book = _book(tokenIndex: 999);

      expect(tokensLeft(book, TimeLeftScope.book), 9000);
    });

    test('the chapter scope counts to the end of the chapter', () {
      final book = _book(tokenIndex: 999, chapterEndIndex: 2000);

      expect(tokensLeft(book, TimeLeftScope.chapter), 1000);
    });

    test('the chapter scope falls back with no chapter recorded', () {
      // A note, a book with no table of contents, a reader in front matter,
      // and a position that has just arrived from another device all land
      // here. Each is a book-shaped answer to a chapter-shaped question,
      // which is legible because no chapter is drawn beside it.
      final book = _book(tokenIndex: 999);

      expect(tokensLeft(book, TimeLeftScope.chapter), 9000);
    });

    test('a chapter end the reader is already past falls back', () {
      // What a kParserVersion bump leaves behind: the index moved, the
      // stored end did not, and the subtraction would go negative.
      final book = _book(
        tokenIndex: 5000,
        chapterTitle: 'Act I',
        chapterEndIndex: 2000,
      );

      expect(tokensLeft(book, TimeLeftScope.chapter), 4999);
    });

    test('a book never opened is counted whole', () {
      expect(tokensLeft(_book(), TimeLeftScope.book), 10000);
    });

    test('a book whose word count predates the column says nothing', () {
      final book = _book(wordCount: 0, tokenIndex: 10);

      expect(tokensLeft(book, TimeLeftScope.book), isNull);
    });

    test('a finished book says nothing', () {
      final book = _book(tokenIndex: 9999);

      expect(tokensLeft(book, TimeLeftScope.book), isNull);
    });
  });

  group('remainingLabel', () {
    test('minutes under an hour', () {
      final book = _book(tokenIndex: 999, chapterEndIndex: 2000);

      expect(
        remainingLabel(book, _steady, TimeLeftScope.chapter),
        '4 min left',
      );
    });

    test('hours and minutes over one', () {
      expect(
        remainingLabel(_book(), _steady, TimeLeftScope.book),
        '40 min left',
      );
      expect(
        remainingLabel(
          _book(wordCount: 100000),
          _steady,
          TimeLeftScope.book,
        ),
        '6 h 40 min left',
      );
    });

    test('elicited pacing counts words, in whichever scope', () {
      final book = _book(tokenIndex: 999, chapterEndIndex: 2000);

      // ADR 0014: nothing moves until the reader presses, so any figure in
      // minutes is a claim about the reader rather than the book. The scope
      // still applies — these are the words left in the chapter.
      expect(
        remainingLabel(book, _elicited, TimeLeftScope.chapter),
        '1000 words left',
      );
      expect(
        remainingLabel(book, _elicited, TimeLeftScope.book),
        '9000 words left',
      );
    });
  });

  group('placeOf', () {
    test('carries the chapter under either scope', () {
      final book = _book(
        tokenIndex: 999,
        chapterTitle: 'Act I, Scene II',
        chapterEndIndex: 2000,
      );

      // The chapter is the label on the figure as much as a fact of its own.
      // Under the book scope it says which chapter the reader is in while
      // the figure counts the book, and both halves stay true.
      expect(placeOf(book, _steady, TimeLeftScope.chapter), (
        chapter: 'Act I, Scene II',
        figure: '4 min left',
      ));
      expect(placeOf(book, _steady, TimeLeftScope.book), (
        chapter: 'Act I, Scene II',
        figure: '36 min left',
      ));
    });

    test('a book with no chapter gives a figure alone', () {
      expect(placeOf(_book(tokenIndex: 999), _steady, TimeLeftScope.chapter), (
        chapter: null,
        figure: '36 min left',
      ));
    });
  });

  group('semanticsForBook', () {
    test('announces the chapter and the figure', () {
      final book = _book(
        tokenIndex: 999,
        chapterTitle: 'Act I, Scene II',
        chapterEndIndex: 2000,
      );

      expect(
        semanticsForBook(book, pacing: _steady),
        'Romeo and Juliet, William Shakespeare, 10 percent read, '
        'Act I, Scene II, 4 min left',
      );
    });

    test('says what it can without a profile yet', () {
      // One frame on a cold start, before watchActiveProfile emits. The node
      // is still a whole book rather than four stops.
      final book = _book(tokenIndex: 999, chapterTitle: 'Act I, Scene II');

      expect(
        semanticsForBook(book),
        'Romeo and Juliet, William Shakespeare, 10 percent read',
      );
    });
  });
}
