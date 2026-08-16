import 'package:flutter/material.dart';

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
