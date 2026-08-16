import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import '../theme/app_tokens.dart';

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

/// What a screen reader says for a book.
String semanticsForBook(BookSummary book) {
  final progress = book.progress;

  final String place;
  if (progress != null) {
    place = '${percentRead(progress)} percent read';
  } else if (book.started) {
    place = 'in progress';
  } else {
    place = 'not started';
  }

  return <String>[book.title, ?book.author, place].join(', ');
}

/// How much of the book is left, in the reader's own pacing.
///
/// One line for the tile on Home, and null when nothing can honestly be
/// said: a book whose `wordCount` predates the column reports zero, and
/// elicited pacing has no duration at all, so the caller falls back to
/// [progressOf]'s words rather than printing a figure nobody can stand
/// behind.
///
/// A book never opened is estimated whole. `tokenIndex` is null there, and
/// zero tokens read is what that means for this question, unlike the
/// question [progressOf] answers.
String? remainingLabel(BookSummary book, PacingConfig pacing) {
  if (book.wordCount <= 0) return null;

  final remaining = book.wordCount - (book.tokenIndex ?? 0);
  if (remaining <= 0) return null;

  final left = remainingReadingTime(
    remainingTokens: remaining,
    config: pacing,
  );
  if (left == null) return '$remaining words left';

  final minutes = left.inMinutes;
  if (minutes < 1) return 'Under a minute left';
  if (minutes < 60) return '$minutes min left';

  final hours = minutes ~/ 60;
  final rest = minutes % 60;

  return rest == 0 ? '$hours h left' : '$hours h $rest min left';
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
