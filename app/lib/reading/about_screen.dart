import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// What this app is, what it is built on, and what it does not claim.
///
/// No version number. The app carries no real one: `pubspec.yaml` still says
/// `1.0.0+1`, which is what `flutter create` wrote, and `package_info_plus`
/// is not a dependency. A number printed here would be a number nobody
/// bumps, which is worse than an absent row.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          Text('hereader', style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'A reader that shows one word at a time in one place, so finding '
            'the next word is not part of reading it.',
            style: theme.textTheme.bodyMedium,
          ),

          const SizedBox(height: AppSpacing.xl),
          Text('Not a medical device', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          // The same sentence as the README's. Both are the project's claim
          // about itself, so they change together or neither changes.
          Text(
            'hereader is not a medical device and makes no therapeutic '
            'claim. It is a reading tool. Nothing in it diagnoses, treats or '
            'measures anything about your sight, and no setting in it is '
            'advice about your sight.',
            style: theme.textTheme.bodyMedium,
          ),

          const SizedBox(height: AppSpacing.xl),
          Text(
            'Where the design comes from',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The presets and the pacing models follow published reading '
            'research, including the findings that argue against parts of '
            'this design. The notes, with every citation checked against its '
            'PMID or DOI, are in docs/research/rsvp-evidence.md in the '
            'repository.',
            style: theme.textTheme.bodyMedium,
          ),

          const SizedBox(height: AppSpacing.xl),
          Text(
            'Your books and your reading',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Books stay on the device you added them to. Signed in, your '
            'place in each book and your reading profiles reach your other '
            'devices; the files do not.',
            style: theme.textTheme.bodyMedium,
          ),

          const SizedBox(height: AppSpacing.xl),
          Text('Source', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          // Text rather than a link. Nothing in the app opens a URL today,
          // and adding url_launcher for one row is a dependency and a
          // per-platform configuration for something a reader can copy.
          SelectableText(
            'github.com/arnasbertulis/hereader',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The reading engine and the EPUB parser are plain Dart packages '
            'in that repository, separate from the app.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
