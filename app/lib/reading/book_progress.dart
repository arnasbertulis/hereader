import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import '../theme/app_tokens.dart';
import 'library_book.dart';
import 'reading_display.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Between the chapter and the figure beside it.
///
/// A middle dot rather than a dash or a bullet: it separates without reading
/// as punctuation belonging to either side, so a chapter title ending in a
/// full stop — which Gutenberg's routinely do — still looks separated.
const _placeSeparator = ' · ';

/// When a note was written, or last edited if it has been since.
///
/// Null for anything that is not a note. An EPUB is never rewritten, and the
/// library already orders on [BookSummary.importedAt] rather than labelling
/// every tile with it, so a book gains no new information from this line —
/// only a note's empty author slot does.
///
/// No `intl` dependency for one fixed format: a reader comparing "Edited"
/// against "Added" wants a specific moment, not a locale-aware calendar, and
/// 24-hour time sidesteps an AM/PM ambiguity that costs more to typeset
/// accessibly than it saves.
String? noteDateLabel(BookSummary book) {
  if (BookSourceFormat.fromName(book.sourceFormat) != BookSourceFormat.note) {
    return null;
  }

  final edited = book.updatedAt != null;
  final at = (book.updatedAt ?? book.importedAt).toLocal();

  final hour = at.hour.toString().padLeft(2, '0');
  final minute = at.minute.toString().padLeft(2, '0');

  return '${edited ? 'Edited' : 'Added'} ${_months[at.month - 1]} '
      '${at.day}, $hour:$minute';
}

/// What the reader is told about their place in a book.
///
/// Three answers, not one bar drawn three ways. A book at zero percent and a
/// book whose progress is unknown look identical as an empty bar, and only
/// one of them is a fact.
({String label, double? value}) progressOf(BookSummary book) {
  final progress = book.progress;

  if (progress != null) {
    return (label: '${percentRead(progress)}%', value: progress);
  }
  if (book.started) return (label: 'In progress', value: null);

  return (label: 'Not started', value: null);
}

int percentRead(double progress) => (progress * 100).round();

/// The words still ahead of the reader, in [scope], or null when no honest
/// count exists.
///
/// The chapter scope falls back to the book rather than reporting nothing,
/// and does so in more cases than "this book has no chapters". A reader in
/// front matter has not reached one, a position synced from another device
/// arrived without one (ADR 0018), and a `chapterEndIndex` left behind by a
/// `kParserVersion` bump can name a token the reader is already past. Each of
/// those is a book-shaped answer to a chapter-shaped question, and it is
/// legible as one because the chapter beside the figure is absent in exactly
/// these cases.
///
/// A book never opened is counted whole. `tokenIndex` is null there, and zero
/// tokens read is what that means for this question — unlike the question
/// [progressOf] answers, which still reports it unstarted.
int? tokensLeft(BookSummary book, TimeLeftScope scope) {
  if (book.wordCount <= 0) return null;

  // tokenIndex + 1, not tokenIndex: the same correction as BookSummary's own
  // progress getter, and for the same reason — the index is the last word
  // *seen*, so treating it as the count already read leaves one word of
  // "remaining" at the true end of the book.
  final read = book.tokenIndex == null ? 0 : book.tokenIndex! + 1;

  if (scope == TimeLeftScope.chapter) {
    final end = book.chapterEndIndex;
    if (end != null && end > read) return end - read;
  }

  final remaining = book.wordCount - read;

  return remaining <= 0 ? null : remaining;
}

/// How much is left, in the reader's own pacing.
///
/// Null when nothing can honestly be said: a book whose `wordCount` predates
/// the column reports zero, and a finished book has nothing ahead of it, so
/// the caller falls back to [progressOf]'s words rather than printing a
/// figure nobody can stand behind.
String? remainingLabel(
  BookSummary book,
  PacingConfig pacing,
  TimeLeftScope scope,
) {
  final remaining = tokensLeft(book, scope);
  if (remaining == null) return null;

  final left = remainingReadingTime(remainingTokens: remaining, config: pacing);
  if (left == null) return '$remaining words left';

  final minutes = left.inMinutes;
  if (minutes < 1) return 'Under a minute left';
  if (minutes < 60) return '$minutes min left';

  final hours = minutes ~/ 60;
  final rest = minutes % 60;

  return rest == 0 ? '$hours h left' : '$hours h $rest min left';
}

/// The two halves of what a tile says about the reader's place.
///
/// Returned apart rather than joined because they truncate differently. The
/// continue tile is 252 logical pixels wide and a chapter title is whatever
/// the publisher wrote, so on most books one of them has to be cut — and it
/// has to be the chapter, since a truncated title still locates the reader
/// while a truncated figure says nothing at all.
///
/// The chapter is present whenever this device recorded one, whichever scope
/// the figure is in. It is the label on the figure as much as a fact of its
/// own: with it, `4 min left` cannot be mistaken for the whole book, and
/// without it there is no chapter for the reader to have meant.
({String? chapter, String? figure}) placeOf(
  BookSummary book,
  PacingConfig pacing,
  TimeLeftScope scope,
) => (chapter: book.chapterTitle, figure: remainingLabel(book, pacing, scope));

/// What a screen reader says for a book.
///
/// Takes the pacing so the chapter and the figure are announced too. A fact
/// added to a tile and not to this is a regression in an app whose premise is
/// that the screen is hard to read.
String semanticsForBook(
  BookSummary book, {
  PacingConfig? pacing,
  TimeLeftScope scope = TimeLeftScope.chapter,
}) {
  final progress = book.progress;

  final String place;
  if (progress != null) {
    place = '${percentRead(progress)} percent read';
  } else if (book.started) {
    place = 'in progress';
  } else {
    place = 'not started';
  }

  // Joined with commas rather than the middle dot the tile draws: a dot is
  // either skipped or spelled out, and neither of those is a pause.
  final where = pacing == null
      ? (chapter: null, figure: null)
      : placeOf(book, pacing, scope);

  return <String>[
    book.title,
    ?book.author,
    place,
    ?where.chapter,
    ?where.figure,
  ].join(', ');
}

/// The chapter and the figure, on one line.
///
/// Shared by the library grid and Home's continue card, so the two cannot
/// grow separate rules for which half gets cut.
class BookPlaceLine extends StatelessWidget {
  final BookSummary book;

  /// Null before the active profile's first emission, which is one frame on a
  /// cold start. The line falls back to [fallback] rather than flickering a
  /// figure in.
  final PacingConfig? pacing;

  final TimeLeftScope scope;

  /// What to say when there is no figure and no chapter — [progressOf]'s
  /// words, on a screen with nowhere else to put them. Null on a screen that
  /// already shows them beside a bar, where this line then draws nothing
  /// rather than repeating itself.
  final String? fallback;

  const BookPlaceLine({
    super.key,
    required this.book,
    required this.pacing,
    required this.scope,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final config = pacing;
    final where = config == null
        ? (chapter: null, figure: null)
        : placeOf(book, config, scope);

    final chapter = where.chapter;
    final figure = where.figure;

    if (chapter == null) {
      final only = figure ?? fallback;
      if (only == null) return const SizedBox.shrink();

      return Text(
        only,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    // The chapter flexes and the figure does not, so a long title is cut and
    // the minutes survive. A single Text with maxLines: 1 would do the
    // opposite at every width that matters.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            chapter,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (figure != null)
          Text('$_placeSeparator$figure', maxLines: 1, style: style),
      ],
    );
  }
}

/// The bar and the percentage, or the words that stand in for them.
///
/// Shared by the library grid and Home's continue card. Two copies would
/// drift into two vocabularies for the same three states, and the reader
/// would meet both on the way from one screen to the other.
class BookProgressLine extends StatelessWidget {
  final BookSummary book;

  const BookProgressLine({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = progressOf(book);

    final label = Text(
      progress.label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        // Percentages that change as the reader moves should not shift the
        // text beside them.
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    if (progress.value == null) return label;

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: LinearProgressIndicator(value: progress.value, minHeight: 4),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        label,
      ],
    );
  }
}
