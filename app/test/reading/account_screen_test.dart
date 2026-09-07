import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/account_screen.dart';
import 'package:app/sync/api_client.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';
import '../test_database.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repository;
  late AuthStore auth;
  late ApiClient api;
  late SyncEngine sync;

  setUp(() async {
    db = AppDatabase(testExecutor());
    repository = LibraryRepository(db);
    auth = AuthStore(storage: FakeSecureStorage());
    api = ApiClient(baseUrl: Uri.parse('http://localhost'), auth: auth);
    sync = SyncEngine(
      repository: repository,
      api: api,
      auth: auth,
      database: db,
    );
    await sync.start();
  });

  tearDown(() async {
    sync.dispose();
    api.dispose();
    auth.dispose();
    await db.close();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccountScreen(api: api, sync: sync),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows a human-recognisable device label, not the raw sync id', (
    tester,
  ) async {
    final rawId = await auth.deviceId();

    await pump(tester);

    expect(find.text('This device'), findsOneWidget);
    // The opaque sync id must never be the thing shown to the reader.
    expect(find.text(rawId), findsNothing);
    expect(
      find.textContaining(RegExp(r'Windows|Mac|Linux|Android|iPhone|Fuchsia')),
      findsOneWidget,
    );
  });
}
