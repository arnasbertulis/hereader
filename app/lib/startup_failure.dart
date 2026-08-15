import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'reading/profile_presentation.dart';

/// Shown when the app cannot finish starting.
///
/// `main` awaits the database, the stored session and the clock before it
/// calls `runApp`, because every write needs a stamp and a half-started app
/// would save positions that cannot be ordered. If any of that throws there
/// is no widget tree at all, and on the web that draws as a blank white
/// page: a failed start and a hung one look the same, and neither says
/// anything.
///
/// Depends on nothing that can have failed. Everything here is a plain
/// widget and a pure colour function.
class StartupFailure extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const StartupFailure({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hereader',
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: Builder(
        builder: (context) {
          final theme = Theme.of(context);

          return Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Hereader could not start',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Your books and reading positions are stored on '
                          'this device and have not been touched.',
                          style: theme.textTheme.bodyLarge,
                        ),
                        if (kIsWeb) ...[
                          const SizedBox(height: 12),
                          // The failure this screen was written for. The
                          // library lives in the browser's own database,
                          // which needs a secure context; served over plain
                          // http on a local network it takes a different
                          // path and can throw before anything is drawn.
                          Text(
                            'In a browser this usually means the page was '
                            'opened over http:// rather than https://, or in '
                            'a private window. Try the https:// address.',
                            style: theme.textTheme.bodyLarge,
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: onRetry,
                          child: const Text('Try again'),
                        ),
                        const SizedBox(height: 24),
                        Text('Details', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 4),
                        // Selectable so it can be pasted into a report. The
                        // reader cannot act on it; whoever they send it to
                        // can.
                        SelectableText(
                          '$error',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
