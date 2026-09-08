import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_tokens.dart';
import '../theme/content_width.dart';

/// Identifies the "View licences" button so tests can find it without
/// depending on its label text.
const Key aboutLicenseButtonKey = Key('about-license-button');

/// What this app is, what it is built on, and what it does not claim.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _resolvedPackageInfo;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _resolvedPackageInfo = info);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ContentWidth(
        maxWidth: AppContent.proseMaxWidth,
        child: ListView(
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
            const SizedBox(height: AppSpacing.sm),
            Text(
              _resolvedPackageInfo == null
                  ? 'Version —'
                  : 'Version ${_resolvedPackageInfo!.version} '
                        '(build ${_resolvedPackageInfo!.buildNumber})',
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
              style: theme.textTheme.bodyMedium,
            ),

            const SizedBox(height: AppSpacing.xl),
            Text('Report a problem', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            SelectableText(
              'github.com/arnasbertulis/hereader/issues, with the version '
              'above.',
              style: theme.textTheme.bodyMedium,
            ),

            const SizedBox(height: AppSpacing.xl),
            Text('About sync', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Sync carries your place in each book and your reading '
              'profiles. It does not carry the books themselves: an EPUB '
              'stays on the device you added it to.\n\n'
              'Changes you make offline are kept and sent the next time the '
              'app reaches the service. Sync also runs by itself every few '
              'minutes while the app is open.\n\n'
              'When two devices land far apart in the same book, the app '
              'asks which place to keep rather than picking one.',
              style: theme.textTheme.bodyMedium,
            ),

            const SizedBox(height: AppSpacing.xl),
            Text('Licence', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'hereader is released under the MIT licence. This screen also '
              'lists the licences of every package it depends on.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: aboutLicenseButtonKey,
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'hereader',
                  applicationVersion: _resolvedPackageInfo == null
                      ? null
                      : '${_resolvedPackageInfo!.version}'
                            ' (build ${_resolvedPackageInfo!.buildNumber})',
                  applicationLegalese:
                      'MIT License—Copyright (c) 2026 '
                      'Arnas Bertulis',
                ),
                child: const Text('View licences'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
