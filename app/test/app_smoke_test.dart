import 'package:app/app_shell.dart';
import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/main.dart';
import 'package:app/reading/home_screen.dart';
import 'package:app/reading/library_screen.dart';
import 'package:app/reading/paste_reader_screen.dart';
import 'package:app/reading/profile_edit_screen.dart';
import 'package:app/reading/profiles_screen.dart';
import 'package:app/reading/reading_display.dart';
import 'package:app/reading/settings_screen.dart';
import 'package:app/sync/api_client.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/last_synced.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:app/theme/app_colors.dart';
import 'package:app/theme/app_icons.dart';
import 'package:app/theme/app_tokens.dart';
import 'package:app/theme/appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'fakes.dart';
import 'test_database.dart';

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
  final ReadingDisplayController display;

  _Harness._({
    required this.database,
    required this.repository,
    required this.auth,
    required this.api,
    required this.sync,
    required this.appearance,
    required this.display,
  });

  factory _Harness.create() {
    final database = AppDatabase(testExecutor());
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
      display: ReadingDisplayController(
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
    display: display,
  );

  Future<void> close() async {
    display.dispose();
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

  testWidgets(
    "Home's empty state opens the same three-way menu the library's add "
    'button does',
    (tester) async {
      final harness = _Harness.create();
      addTearDown(harness.close);

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      // Used to be two buttons of Home's own — EPUB and paste, with no way
      // to reach the note editor from here at all. One button opening the
      // library's own menu is what fixed that, rather than teaching this
      // screen a third button of its own to keep in step with the other
      // two.
      await tester.tap(find.text('Add something to read'));
      await tester.pumpAndSettle();

      expect(find.text('Add an EPUB'), findsOneWidget);
      expect(find.text('Write a note'), findsOneWidget);
      expect(find.text('Paste text'), findsOneWidget);

      await _disposeTree(tester);
    },
  );

  testWidgets('shows a book that is already stored', (tester) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await harness.repository.addBook(
      fixtureBook(
        id: 'test-1',
        title: 'Romeo and Juliet',
        author: 'William Shakespeare',
        wordCount: 25000,
      ),
      Uint8List.fromList([1, 2, 3]),
    );

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    // Home is the tab that shows first, so this is the continue card. The
    // library is offstage behind it with the same book in its grid.
    expect(find.text('Romeo and Juliet'), findsOneWidget);
    expect(find.text('William Shakespeare'), findsOneWidget);
    expect(find.byKey(homeContinueTileKey), findsOneWidget);
    // A book with a word count and no position is estimated whole, so the
    // tile says how long it will take rather than that it is unstarted.
    // Matched loosely: the figure is the active preset's rate, and pinning
    // the string here would make this test fail the day that preset is
    // retuned.
    expect(
      find.descendant(
        of: find.byKey(homeContinueTileKey),
        matching: find.textContaining('left'),
      ),
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
      fixtureBook(
        id: 'read-first',
        title: 'Romeo and Juliet',
        wordCount: 25000,
      ),
      Uint8List.fromList([1]),
    );
    await harness.repository.addBook(
      fixtureBook(id: 'added-later', title: 'Hamlet', wordCount: 30000),
      Uint8List.fromList([2]),
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

    // The tile holds one book, so which title is inside it is the whole
    // assertion. Hamlet is on the screen either way, in the recent row.
    final tile = find.byKey(homeContinueTileKey);
    expect(
      find.descendant(of: tile, matching: find.text('Romeo and Juliet')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile, matching: find.text('Hamlet')),
      findsNothing,
    );

    // A book with a percentage shows it as the bar along the tile's bottom
    // edge, so the words that stand in for one are absent.
    expect(find.text('Not started'), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets('offers signing in when there is no session', (tester) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    // Sync reports itself in Settings. The library carried this control
    // until the add button took its bar, and Home carried a copy before
    // that.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    // The index row answers without being opened, which is what every row on
    // that screen is for.
    expect(find.text('Off. Sign in to turn it on.'), findsOneWidget);
    expect(find.text('Not signed in'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Sync'));
    await tester.pumpAndSettle();

    // Reading works signed out, so this is an invitation rather than a gate.
    // It says where to go rather than offering a button that would take the
    // reader somewhere they did not ask to be.
    expect(find.byIcon(AppIcons.syncSignedOut), findsOneWidget);
    expect(find.text('Sync is off'), findsOneWidget);
    expect(find.text('Sign in under Account to turn sync on.'), findsOneWidget);

    // And the run button is off, since there is nothing to run against.
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Sync now'))
          .onPressed,
      isNull,
    );

    await _disposeTree(tester);
  });

  testWidgets('the paste screen enables reading once there is text', (
    tester,
  ) async {
    final database = AppDatabase(testExecutor());
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

  testWidgets('the profile list holds presets and none of the reader own', (
    tester,
  ) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await tester.pumpWidget(
      MaterialApp(
        home: ProfilesScreen(
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
        home: ProfilesScreen(
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

    // A copy is what the reader asked to make and is about to customise, so
    // it becomes the active profile as soon as it exists rather than only
    // when the source happened to be active already.
    expect((await harness.repository.activeProfile()).id, mine.single.id);

    await _disposeTree(tester);
  });

  testWidgets('a preset opens read-only with a way to copy it', (tester) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await tester.pumpWidget(
      MaterialApp(
        home: ProfilesScreen(
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
    // the paste screen stands in. Home's empty state opens the same add
    // menu the library's own button does, and the library's app bar is
    // offstage behind Home.
    await tester.tap(find.text('Add something to read'));
    await tester.pumpAndSettle();
    // Free books now sits above it in the menu, pushing this option below
    // the dialog's own viewport at this window size.
    await tester.ensureVisible(find.text('Paste text'));
    await tester.tap(find.text('Paste text'));
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

    await tester.tap(find.byIcon(AppIcons.tabSettings));
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

    expect(find.byKey(appNavBarKey), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    tester.view.physicalSize = const Size(900, 800);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byKey(appNavBarKey), findsNothing);

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
      tester.getSize(find.byKey(appNavBarKey)).height,
      greaterThan(AppNav.barHeight),
    );
    expect(tester.takeException(), isNull);

    await _disposeTree(tester);
  });

  testWidgets('settings is an index of sections, not one long scroll', (
    tester,
  ) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.tabSettings));
    await tester.pumpAndSettle();

    for (final section in const [
      'Account',
      'Reading profiles',
      'Appearance',
      'Reading',
      'Sync',
      'About',
    ]) {
      expect(find.text(section), findsOneWidget);
    }

    // The row states where it leads rather than only naming a section.
    expect(find.text('Not signed in'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('the profiles row pushes the list that used to be settings', (
    tester,
  ) async {
    final harness = _Harness.create();
    addTearDown(harness.close);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.tabSettings));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reading profiles'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfilesScreen), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);

    await _disposeTree(tester);
  });

  test('the accent is named where the reader picked a named one', () {
    expect(
      describeAppearance(
        AppearanceSettings(
          themeMode: ThemeMode.dark,
          accent: AppAccents.rust.color,
          highContrast: false,
        ),
      ),
      'Dark · Rust',
    );

    // A colour off the sliders belongs to no entry in the list, and the row
    // says so rather than printing six hex digits at the reader.
    expect(
      describeAppearance(
        AppearanceSettings(
          themeMode: ThemeMode.light,
          accent: const Color(0xFF123456),
          highContrast: true,
        ),
      ),
      'Light · Custom · High contrast',
    );
  });

  test('a sync that has never run says so rather than reporting a time', () {
    final now = DateTime.utc(2026, 5, 1, 12);

    expect(describeLastSynced(null), 'Not synced on this device yet');
    expect(
      describeLastSynced(now.subtract(const Duration(seconds: 20)), now: now),
      'Synced just now',
    );
    expect(
      describeLastSynced(now.subtract(const Duration(minutes: 1)), now: now),
      'Synced 1 minute ago',
    );
    expect(
      describeLastSynced(now.subtract(const Duration(hours: 5)), now: now),
      'Synced 5 hours ago',
    );

    // Devices disagree about the hour more often than anyone expects, and a
    // stored time ahead of this clock should not read as the future.
    expect(
      describeLastSynced(now.add(const Duration(hours: 3)), now: now),
      'Synced recently',
    );
  });

  test('a book never opened is ordered by when it arrived', () {
    final read = BookSummary(
      id: 'read',
      title: 'Read',
      wordCount: 10,
      importedAt: DateTime.utc(2026, 1, 1),
      sourceFormat: 'epub',
      lastReadAt: DateTime.utc(2026, 1, 2),
    );
    final imported = BookSummary(
      id: 'imported',
      title: 'Imported',
      wordCount: 10,
      importedAt: DateTime.utc(2026, 1, 3),
      sourceFormat: 'epub',
    );

    // The import is newer than the reading, so it leads. Falling back to a
    // null date instead would bury every book the reader has not opened
    // under one they finished months ago.
    expect(byLastRead([read, imported]).first.id, 'imported');
    expect(byLastRead([imported, read]).first.id, 'imported');
  });

  test('a tied timestamp still favours the book that has been opened', () {
    // Drift's whole-second precision can round two real-clock writes onto
    // the same stored value, which is exactly what this pins: the tie
    // itself, not a difference small enough to disappear in rounding.
    final tie = DateTime.utc(2026, 1, 1);
    final read = BookSummary(
      id: 'read',
      title: 'Read',
      wordCount: 10,
      importedAt: tie,
      sourceFormat: 'epub',
      lastReadAt: tie,
    );
    final imported = BookSummary(
      id: 'imported',
      title: 'Imported',
      wordCount: 10,
      importedAt: tie,
      sourceFormat: 'epub',
    );

    expect(byLastRead([read, imported]).first.id, 'read');
    expect(byLastRead([imported, read]).first.id, 'read');
  });
}
