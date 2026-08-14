import 'dart:async';

import 'package:flutter/material.dart';

import 'data/database.dart';
import 'data/library_repository.dart';
import 'reading/library_screen.dart';
import 'reading/profile_presentation.dart';
import 'sync/api_client.dart';
import 'sync/auth_store.dart';
import 'sync/position_conflict_sheet.dart';
import 'sync/sync_engine.dart';

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

  final database = AppDatabase();
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

  // Not awaited: a slow or unreachable server must not delay the library
  // appearing. Reading works whether or not this succeeds.
  unawaited(sync.syncNow());

  runApp(HereaderApp(repository: repository, sync: sync, api: api));
}

class HereaderApp extends StatelessWidget {
  final LibraryRepository repository;
  final SyncEngine sync;
  final ApiClient api;

  HereaderApp({
    super.key,
    required this.repository,
    required this.sync,
    required this.api,
  });

  /// Lets the conflict watcher present a sheet over whatever route is
  /// showing, including the reading surface.
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hereader',
      // The library, settings and sign-in follow the platform. The reading
      // surface does not: which polarity the text is drawn in is a per-profile
      // setting, so the reader screen builds its own chrome theme from the
      // active profile rather than inheriting either of these. See
      // `readerChromeTheme`.
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      navigatorKey: _navigatorKey,
      // Above the app rather than inside a screen, so a divergence arriving
      // during a periodic sync is asked about wherever the reader is.
      builder: (context, child) => ConflictWatcher(
        repository: repository,
        sync: sync,
        navigatorKey: _navigatorKey,
        child: child ?? const SizedBox.shrink(),
      ),
      home: LibraryScreen(repository: repository, sync: sync, api: api),
    );
  }
}
