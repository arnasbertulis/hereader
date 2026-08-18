import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_tokens.dart';
import 'reading_display.dart';
import 'setting_slider.dart';

/// What the app does while a book is open — one setting, and the rest stated
/// rather than configured.
///
/// The page exists because these are the things a reader asks about after
/// losing a place or pressing a key that did nothing, and the answers were
/// only in the ADRs.
///
/// It carried no setting at all until the time-left scope arrived, and the
/// note here said so as though writing a preference were the thing ruled
/// out. What is actually ruled out is narrower: a setting whose wrong value
/// costs the reader their place. A switch that turns off position saving, or
/// a slider on the fifteen-second cadence, is still not going here. Which of
/// two honest figures a tile shows is not that kind of setting, and neither
/// is how far one tap moves — a step the reader dislikes is undone by the
/// step back beside it.
class ReadingSettingsScreen extends StatelessWidget {
  final ReadingDisplayController display;

  const ReadingSettingsScreen({super.key, required this.display});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Reading')),
      body: ListenableBuilder(
        listenable: display,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            const _SectionHeader('Step'),
            SettingSlider(
              label: 'One step moves',
              value: display.stepWords.toDouble(),
              valueLabel:
                  '${display.stepWords} '
                  'word${display.stepWords == 1 ? '' : 's'}',
              min: kMinStepWords.toDouble(),
              max: kMaxStepWords.toDouble(),
              divisions: kMaxStepWords - kMinStepWords,
              help:
                  'Tapping the left or right quarter of the reading surface '
                  'moves this far and stops there. The Left and Right keys do '
                  'the same. Starting again picks up where you stopped rather '
                  'than stepping back the way it does after a pause.',
              onChanged: (v) => display.setStepWords(v.round()),
            ),
            const Divider(),
            const _SectionHeader('Time left counts'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SegmentedButton<TimeLeftScope>(
                segments: const [
                  ButtonSegment(
                    value: TimeLeftScope.chapter,
                    label: Text('This chapter'),
                  ),
                  ButtonSegment(
                    value: TimeLeftScope.book,
                    label: Text('Whole book'),
                  ),
                ],
                selected: {display.timeLeftScope},
                onSelectionChanged: (selected) =>
                    display.setTimeLeftScope(selected.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Text(
                'On the home and library tiles. The chapter you are in is '
                'shown either way; books without a table of contents, and '
                'places that have just arrived from another device, count '
                'down to the end of the book.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const Divider(),
            const ListTile(
              leading: Icon(AppIcons.placeIsSaved),
              title: Text('Your place is saved as you read'),
              subtitle: Text(
                'Every fifteen seconds while words are moving, at every pause, '
                'and when you leave the book or the app.',
              ),
            ),
            const ListTile(
              leading: Icon(AppIcons.pausesWhenHidden),
              title: Text('Playback pauses when the app is hidden'),
              subtitle: Text(
                'Switching apps stops the words rather than running the book '
                'on without you.',
              ),
            ),
            const ListTile(
              leading: Icon(AppIcons.frontMatterOffered),
              title: Text('Front matter is offered, not skipped for you'),
              subtitle: Text(
                'A book that opens on a title page and a licence offers to '
                'jump to the first chapter, and stays where it is if you '
                'ignore it.',
              ),
            ),
            const ListTile(
              leading: Icon(AppIcons.chaptersFromTheBook),
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
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.xl,
      AppSpacing.lg,
      AppSpacing.sm,
    ),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _Shortcut {
  final String action;
  final String keys;

  const _Shortcut(this.action, this.keys);
}

const _shortcuts = [
  _Shortcut('Start or pause', 'Space'),
  _Shortcut('Back a step', 'Left'),
  _Shortcut('Forward a step', 'Right'),
  _Shortcut('Chapters', 'C'),
  _Shortcut('Close the book', 'Escape'),
];
