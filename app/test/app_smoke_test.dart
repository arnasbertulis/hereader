import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';
import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_screen.dart';
import 'package:app/reading/paste_reader_screen.dart';
import 'package:app/sync/api_client.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/sync_engine.dart';

/// Everything the app needs, wired against an in-memory database.
///
/// Nothing here reaches the network: sync only runs when a session exists,
/// and no test signs in.
class _Harness {
  final AppDatabase database;
  final LibraryRepository repository;
  final AuthStore auth;
  final ApiClient api;
  final SyncEngine sync;

  _Harness._({
    required this.database,
    required this.repository,
    required this.auth,
    required this.api,
    required this.sync,
  });

  factory _Harness.create() {
    final database = AppDatabase(NativeDatabase.memory());
    final repository = LibraryRepository(database);
    final auth = AuthStore();
    final api = ApiClient(baseUrl: Uri.parse('http://localhost'), auth: auth);

    return _Harness._(
      database: database,
      repository: repository,
      auth: auth,
      api: api,
      sync: SyncEngine(
        repository: repository,
        api: api,
        auth: auth,
        database: database,
      ),
    );
  }

  Widget get app => HereaderApp(repository: repository, sync: sync, api: api);

  Future<void> close() async {
    sync.dispose();
    api.dispose();
    auth.dispose();
    await database.close();
  }
}

/// Disposes the widget tree inside the test body.
///
/// Drift schedules a zero-duration timer when a query stream is cancelled.
/// Left to teardown it is never pumped and the framework reports a leaked
/// timer, so the pump has to advance the clock.
Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  testWidgets('launches into an empty library', (tester) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await tester.pumpWidget(harness.app);

    expect(find.byType(LibraryScreen), findsOneWidget);

    // The library comes from a stream, so the first frame is a spinner.
    await tester.pumpAndSettle();
    expect(find.text('No books yet'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('shows a book that is already stored', (tester) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await harness.repository.addBook(
      id: 'test-1',
      title: 'Romeo and Juliet',
      author: 'William Shakespeare',
      bytes: Uint8List.fromList([1, 2, 3]),
      wordCount: 25000,
    );

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    expect(find.text('Romeo and Juliet'), findsOneWidget);
    expect(find.text('William Shakespeare'), findsOneWidget);
    expect(find.text('25000 words'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('offers signing in when there is no session', (tester) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    // Reading works signed out, so this is an invitation rather than a gate.
    expect(
      find.widgetWithIcon(IconButton, Icons.cloud_off_outlined),
      findsOneWidget,
    );

    await _disposeTree(tester);
  });

  testWidgets('the paste screen enables reading once there is text', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PasteReaderScreen()));

    var button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Read this'),
    );
    expect(button.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Labas rytas.');
    await tester.pump();

    button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Read this'),
    );
    expect(button.onPressed, isNotNull);
  });
}
