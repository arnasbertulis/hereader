import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';
import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_screen.dart';
import 'package:app/reading/paste_reader_screen.dart';
import 'package:app/reading/profile_edit_screen.dart';
import 'package:app/reading/settings_screen.dart';
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

/// A stamp, without starting a sync engine.
///
/// Screens take a `Future<String> Function()` rather than the engine itself,
/// which is what lets a widget test supply this instead of standing up a
/// clock, an auth store and a device id it has no use for.
Future<String> _stamp() async => '0000000000001-00000-test';

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
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      MaterialApp(
        home: PasteReaderScreen(
          repository: LibraryRepository(database),
          issueStamp: _stamp,
        ),
      ),
    );

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

  testWidgets('settings lists the presets and no profiles of the reader own', (
    tester,
  ) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          repository: harness.repository,
          issueStamp: _stamp,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Central field loss'), findsOneWidget);
    expect(
      find.text('None yet. Copy a preset below to make one you can change.'),
      findsOneWidget,
    );

    await _disposeTree(tester);
  });

  testWidgets('copying a preset produces an editable profile', (tester) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          repository: harness.repository,
          issueStamp: _stamp,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // With nothing of the reader's own yet, the first row is a preset.
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Make a copy'));
    await tester.pumpAndSettle();

    // The copy is stored and the reader lands in the editor on it, rather
    // than back in the list wondering whether anything happened.
    expect(find.byType(ProfileEditScreen), findsOneWidget);

    final mine = (await harness.repository.allProfiles())
        .where((p) => !p.isBuiltIn)
        .toList();

    expect(mine, hasLength(1));
    expect(mine.single.name, endsWith('(copy)'));

    // The preset it came from is untouched, which is the whole reason
    // editing one produces a copy.
    expect(mine.single.id, isNot(startsWith('builtin.')));

    await _disposeTree(tester);
  });

  testWidgets('a preset opens read-only with a way to copy it', (tester) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          repository: harness.repository,
          issueStamp: _stamp,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('View settings'));
    await tester.pumpAndSettle();

    expect(find.text('Make an editable copy'), findsOneWidget);

    // Nothing was stored by opening it.
    final mine = (await harness.repository.allProfiles())
        .where((p) => !p.isBuiltIn)
        .toList();
    expect(mine, isEmpty);

    await _disposeTree(tester);
  });
}
