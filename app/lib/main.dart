import 'dart:async';

import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'data/database.dart';
import 'data/library_repository.dart';
import 'reading/reading_display.dart';
import 'startup_failure.dart';
import 'sync/api_client.dart';
import 'sync/auth_store.dart';
import 'sync/position_conflict_sheet.dart';
import 'sync/sync_engine.dart';
import 'theme/app_theme.dart';
import 'theme/appearance.dart';

/// Where the sync service lives.
///
/// Overridable at build time so a release build points at the deployed
/// service without the URL being edited by hand:
///
///   flutter run --dart-define=HEREADER_API=https://api.example.com
const _apiBase = String.fromEnvironment(
  'HEREADER_API',
  defaultValue: 'http://localhost:8080/api',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _start();
}

/// Builds the object graph and hands it to `runApp`.
///
/// Everything is awaited before the first frame because every write needs a
/// clock stamp and a resolved session; an app that started without them
/// would save positions that cannot be ordered. That means a failure has to
/// be caught here, since there is no widget tree yet to catch it — and on
/// the web an uncaught one draws nothing at all.
///
/// Separated from `main` so the failure screen can call it again.
Future<void> _start() async {
  AppDatabase? database;

  try {
    database = AppDatabase();
    final repository = LibraryRepository(database);

    final auth = AuthStore();
    final api = ApiClient(baseUrl: Uri.parse(_apiBase), auth: auth);

    final sync = SyncEngine(
      repository: repository,
      api: api,
      auth: auth,
      database: database,
    );

    // A stored session and the clock both have to be ready before anything
    // writes, because every write needs a stamp.
    await auth.restore();
    await sync.start();

    // Also before the first frame. Reading appearance after first paint
    // means a white flash on a dark-theme device on every cold start, which
    // is worse than usual for a reader who chose a dark theme because bright
    // light is uncomfortable.
    final appearance = AppearanceController(
      repository: repository,
      issueStamp: sync.issueStamp,
    );
    await appearance.restore();

    // Restored on the same path and for a milder version of the same reason:
    // reading it after the first frame would draw the continue tile with the
    // default scope and correct it a frame later, in front of the reader.
    final display = ReadingDisplayController(
      repository: repository,
      issueStamp: sync.issueStamp,
    );
    await display.restore();

    // Not awaited: a slow or unreachable server must not delay the library
    // appearing. Reading works whether or not this succeeds.
    unawaited(sync.syncNow());

    runApp(
      HereaderApp(
        repository: repository,
        sync: sync,
        api: api,
        appearance: appearance,
        display: display,
      ),
    );
  } catch (error, stack) {
    // Shown and printed: the screen carries the message for the reader, the
    // console carries the trace for whoever they send it to.
    debugPrint('Hereader failed to start: $error\n$stack');

    if (database != null) {
      try {
        await database.close();
      } catch (_) {
        // A close that fails during a failed start has nothing to add. The
        // first error is the one worth reporting.
      }
    }

    // Closed above, because a retry that opened a second connection would
    // fail for its own reason and hide the original.
    runApp(StartupFailure(error: error, onRetry: () => unawaited(_start())));
  }
}

class HereaderApp extends StatefulWidget {
  final LibraryRepository repository;
  final SyncEngine sync;
  final ApiClient api;
  final AppearanceController appearance;
  final ReadingDisplayController display;

  const HereaderApp({
    super.key,
    required this.repository,
    required this.sync,
    required this.api,
    required this.appearance,
    required this.display,
  });

  @override
  State<HereaderApp> createState() => _HereaderAppState();
}

/// Stateful so the navigator key survives a rebuild.
///
/// This was a `StatelessWidget` holding the `GlobalKey` as a field, which
/// worked only because nothing ever rebuilt it. Appearance changes rebuild
/// it now, and a fresh key on each rebuild would hand the `Navigator` a new
/// identity and throw away every route under it — including the book the
/// reader is in.
class _HereaderAppState extends State<HereaderApp> {
  /// Lets the conflict watcher present a sheet over whatever route is
  /// showing, including the reading surface.
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appearance,
      builder: (context, _) {
        final appearance = widget.appearance.settings;

        return MaterialApp(
          title: 'Hereader',
          // The shell, its tabs and sign-in follow the reader's stored
          // choice, defaulting to the platform. The reading surface
          // does not: which polarity the text is drawn in is a per-profile
          // setting, so the reader screen builds its own chrome theme from
          // the active profile rather than inheriting any of these. See
          // `readerChromeTheme`.
          theme: appTheme(
            brightness: Brightness.light,
            accent: appearance.accent,
            highContrast: appearance.highContrast,
          ),
          darkTheme: appTheme(
            brightness: Brightness.dark,
            accent: appearance.accent,
            highContrast: appearance.highContrast,
          ),
          // Used by the framework when the platform itself reports a
          // high-contrast preference, which is how a reader who set it at
          // the operating system level gets it here without finding the
          // switch. The app's own switch forces it on regardless, so the
          // effective rule is either one.
          highContrastTheme: appTheme(
            brightness: Brightness.light,
            accent: appearance.accent,
            highContrast: true,
          ),
          highContrastDarkTheme: appTheme(
            brightness: Brightness.dark,
            accent: appearance.accent,
            highContrast: true,
          ),
          themeMode: appearance.themeMode,
          navigatorKey: _navigatorKey,
          // Above the app rather than inside a screen, so a divergence
          // arriving during a periodic sync is asked about wherever the
          // reader is.
          builder: (context, child) => ConflictWatcher(
            repository: widget.repository,
            sync: widget.sync,
            navigatorKey: _navigatorKey,
            child: child ?? const SizedBox.shrink(),
          ),
          // The shell, not a screen. Everything outside a book is a tab
          // inside it, and the reader is pushed above it.
          home: AppShell(
            repository: widget.repository,
            sync: widget.sync,
            api: widget.api,
            appearance: widget.appearance,
            display: widget.display,
          ),
        );
      },
    );
  }
}
