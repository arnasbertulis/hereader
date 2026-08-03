import 'dart:async';

import 'package:flutter/material.dart';

import 'data/database.dart';
import 'data/library_repository.dart';
import 'reading/library_screen.dart';
import 'sync/api_client.dart';
import 'sync/auth_store.dart';
import 'sync/sync_engine.dart';

/// Where the sync service lives.
///
/// Overridable at build time so a release build points at the deployed
/// service without the URL being edited by hand:
///
///   flutter run --dart-define=HEREADER_API=https://api.example.com
const _apiBase = String.fromEnvironment(
  'HEREADER_API',
  defaultValue: 'http://localhost:8080',
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

  const HereaderApp({
    super.key,
    required this.repository,
    required this.sync,
    required this.api,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hereader',
      theme: ThemeData(useMaterial3: true),
      home: LibraryScreen(repository: repository, sync: sync, api: api),
    );
  }
}
