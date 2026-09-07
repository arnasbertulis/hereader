import 'package:app/data/database.dart' hide PositionConflict;
import 'package:app/data/library_repository.dart';
import 'package:app/reading/info_dot.dart';
import 'package:app/reading/sync_screen.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'test_database.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repository;
  late AuthStore auth;
  late FakeApi api;
  late SyncEngine sync;

  setUp(() async {
    db = AppDatabase(testExecutor());
    repository = LibraryRepository(db);
    auth = AuthStore(storage: FakeSecureStorage());
    await auth.save(
      const Session(accessToken: 'access', refreshToken: 'refresh'),
    );
    api = FakeApi(auth: auth);
    sync = SyncEngine(
      repository: repository,
      api: api,
      auth: auth,
      database: db,
    );
  });

  tearDown(() => db.close());

  Finder infoDotFor(String semanticLabel) => find.byWidgetPredicate(
    (w) => w is InfoDot && w.semanticLabel == semanticLabel,
  );

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SyncScreen(repository: repository, api: api, sync: sync),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('About sync', () {
    testWidgets('prints no explanation by default, only the (i)', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.textContaining('Sync carries your place'), findsNothing);
      expect(infoDotFor('About sync'), findsOneWidget);
    });

    testWidgets('reveals the explanation on tap', (tester) async {
      await pumpScreen(tester);

      await tester.tap(infoDotFor('About sync'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sync carries your place'), findsOneWidget);
    });
  });
}
