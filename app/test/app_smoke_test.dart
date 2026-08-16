import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/main.dart';
import 'package:app/reading/home_screen.dart';
import 'package:app/reading/library_screen.dart';
import 'package:app/reading/paste_reader_screen.dart';
import 'package:app/reading/profile_edit_screen.dart';
import 'package:app/reading/settings_screen.dart';
import 'package:app/sync/api_client.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:app/theme/app_colors.dart';
import 'package:app/theme/app_tokens.dart';
import 'package:app/theme/appearance.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

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
  final AppearanceController appearance;

  _Harness._({
    required this.database,
    required this.repository,
    required this.auth,
    required this.api,
    required this.sync,
    required this.appearance,
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
      // Takes `_stamp` rather than `sync.issueStamp`, since no test starts
      // the engine and issuing a stamp without a clock is a StateError.
      appearance: AppearanceController(
        repository: repository,
        issueStamp: _stamp,
      ),
    );
  }

  Widget get app => HereaderApp(
    repository: repository,
    sync: sync,
    api: api,
    appearance: appearance,
  );

  Future<void> close() async {
    appearance.dispose();
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

/// The accent currently in force, read from inside the tree rather than
/// from the controller, so this measures what the app is painting.
Color _primaryOf(WidgetTester tester, Finder screen) =>
    Theme.of(tester.element(screen)).colorScheme.primary;

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
  testWidgets('launches into home with nothing to continue', (tester) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await tester.pumpWidget(harness.app);

    expect(find.byType(HomeScreen), findsOneWidget);

    // The library comes from a stream, so the first frame is a spinner.
    await tester.pumpAndSettle();
    expect(find.text('Nothing open yet'), findsOneWidget);

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

    // Home is the tab that shows first, so this is the continue card. The
    // library is offstage behind it with the same book in its grid.
    expect(find.text('Romeo and Juliet'), findsOneWidget);
    expect(find.text('William Shakespeare'), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Start reading'),
      findsOneWidget,
    );

    await _disposeTree(tester);
  });

  testWidgets('home continues the book read last, not the one added last', (
    tester,
  ) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await harness.repository.addBook(
      id: 'read-first',
      title: 'Romeo and Juliet',
      bytes: Uint8List.fromList([1]),
      wordCount: 25000,
    );
    await harness.repository.addBook(
      id: 'added-later',
      title: 'Hamlet',
      bytes: Uint8List.fromList([2]),
      wordCount: 30000,
    );

    // Read the older import, which is the whole point of the ordering: the
    // library would put Hamlet first and Home should not.
    await harness.repository.savePosition(
      bookId: 'read-first',
      locator: Locator(blockId: 'b1', charOffset: 0, parserVersion: 1),
      hlc: await _stamp(),
      tokenIndex: 5000,
    );

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    // Continue rather than Start reading is what a started book gets, so
    // one of them means the card picked the book with a position.
    expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start reading'), findsNothing);
    expect(find.text('20%'), findsOneWidget);

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
          appearance: harness.appearance,
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
          appearance: harness.appearance,
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
          appearance: harness.appearance,
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

  testWidgets('an appearance change rethemes and keeps the route', (
    tester,
  ) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    // A pushed route, not a tab. What this covers is a GlobalKey identity
    // change taking the Navigator's stack with it, and a tab never goes on
    // that stack. Settings used to be pushed and is one of the tabs now, so
    // the paste screen stands in. Home's empty state offers it, and the
    // library's app bar is offstage behind Home.
    await tester.tap(find.byIcon(Icons.content_paste));
    await tester.pumpAndSettle();

    final pasted = find.byType(PasteReaderScreen);
    expect(pasted, findsOneWidget);

    final before = _primaryOf(tester, pasted);

    await harness.appearance.setAccent(AppAccents.rust.color);
    await tester.pumpAndSettle();

    expect(_primaryOf(tester, pasted), isNot(before));

    // HereaderApp held its navigator key as a field of a StatelessWidget,
    // which was safe only while nothing rebuilt it. An appearance change
    // rebuilds it now, and a fresh GlobalKey would hand the Navigator a new
    // identity and take every pushed route down with it — including a book
    // the reader is in the middle of.
    expect(pasted, findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('a tab change swaps the screen and keeps the other alive', (
    tester,
  ) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);

    // Offstage rather than disposed. Home holds a drift subscription and a
    // scroll offset that a rebuilt subtree would lose, which is the whole
    // reason the tabs sit in a stack.
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(LibraryScreen, skipOffstage: false), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('control and a digit reach a tab', (tester) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    // Digit 3 rather than 2, since Home took the first slot and the
    // shortcut list is indexed alongside the destinations.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('a wide window navigates with the rail', (tester) async {
    final harness = _Harness.create();
    addTearDown(harness.close);
    addTearDown(tester.view.reset);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    tester.view.physicalSize = const Size(900, 800);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets('the navigation bar grows with the reader text size', (
    tester,
  ) async {
    final harness = _Harness.create();
    addTearDown(harness.close);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    tester.platformDispatcher.textScaleFactorTestValue = 2;

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    // The height is a base plus whatever the scaled label needs. Nothing
    // clamps the scaler, so the bar has to absorb it rather than clip, and
    // an overflow here is an exception rather than a quiet stripe.
    expect(
      tester.getSize(find.byType(NavigationBar)).height,
      greaterThan(AppNav.barHeight),
    );
    expect(tester.takeException(), isNull);

    await _disposeTree(tester);
  });

  test('a book never opened is ordered by when it arrived', () {
    final read = BookSummary(
      id: 'read',
      title: 'Read',
      wordCount: 10,
      importedAt: DateTime.utc(2026, 1, 1),
      lastReadAt: DateTime.utc(2026, 1, 2),
    );
    final imported = BookSummary(
      id: 'imported',
      title: 'Imported',
      wordCount: 10,
      importedAt: DateTime.utc(2026, 1, 3),
    );

    // The import is newer than the reading, so it leads. Falling back to a
    // null date instead would bury every book the reader has not opened
    // under one they finished months ago.
    expect(byLastRead([read, imported]).first.id, 'imported');
    expect(byLastRead([imported, read]).first.id, 'imported');
  });
}
