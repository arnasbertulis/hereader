import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// What the app does while a book is open, stated rather than configured.
///
/// Every item here is a fixed behaviour today. The page exists because these
/// are the things a reader asks about after losing a place or pressing a key
/// that did nothing, and the answers were only in the ADRs.
///
/// Nothing on this page writes a preference. A switch that turns off
/// position saving, or a slider on the fifteen-second cadence, would be a
/// setting whose wrong value costs the reader their place, and neither has a
/// reason to exist yet.
class ReadingSettingsScreen extends StatelessWidget {
  const ReadingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Reading')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          const ListTile(
            leading: Icon(Icons.bookmark_outline),
            title: Text('Your place is saved as you read'),
            subtitle: Text(
              'Every fifteen seconds while words are moving, at every pause, '
              'and when you leave the book or the app.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.pause_circle_outline),
            title: Text('Playback pauses when the app is hidden'),
            subtitle: Text(
              'Switching apps stops the words rather than running the book '
              'on without you.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.first_page_outlined),
            title: Text('Front matter is offered, not skipped for you'),
            subtitle: Text(
              'A book that opens on a title page and a licence offers to '
              'jump to the first chapter, and stays where it is if you '
              'ignore it.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.list_alt_outlined),
            title: Text('Chapters come from the book'),
            subtitle: Text(
              'The chapter list is the one the publisher wrote. A book that '
              'ships without one shows no chapter button rather than a list '
              'guessed from its headings.',
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              'Keys while reading',
              style: theme.textTheme.titleMedium,
            ),
          ),
          for (final shortcut in _shortcuts)
            ListTile(
              title: Text(shortcut.action),
              trailing: Text(
                shortcut.keys,
                style: theme.textTheme.labelLarge,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              'Ctrl and a digit reach the tabs outside a book. Inside one, '
              'the keys above belong to the reader.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Shortcut {
  final String action;
  final String keys;

  const _Shortcut(this.action, this.keys);
}

const _shortcuts = [
  _Shortcut('Start or pause', 'Space'),
  _Shortcut('Back one word', 'Left'),
  _Shortcut('Forward one word', 'Right'),
  _Shortcut('Chapters', 'C'),
  _Shortcut('Close the book', 'Escape'),
];
