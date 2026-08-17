import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/reader_screen.dart';
import 'package:app/reading/rsvp_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

Future<String> _stamp() async => '0000000000001-00000-test';

/// Sixteen tokens, so a second of playback at the default rate moves a
/// visible distance without reaching the end.
TokenizedText _text() => TokenizedText.from(const [
  (id: 'one', text: 'Alpha beta gamma delta epsilon zeta eta theta.'),
  (id: 'two', text: 'Iota kappa lambda mu nu xi omicron pi.'),
], parserVersion: 1);

double _progress(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
    .value!;

void main() {
  late AppDatabase database;
  late TokenizedText text;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    text = _text();
  });

  tearDown(() => database.close());

  /// No `theme:`, so `AppChromeSource.of` falls back rather than reading an
  /// extension. That path is load-bearing for every test in this file;
  /// `reader_chrome_test.dart` is what holds the fallback to the app's
  /// default accent.
  Widget reader() => MaterialApp(
    home: ReaderScreen(
      book: LibraryBook(id: 'b', title: 'A Book', text: text),
      repository: LibraryRepository(database),
      issueStamp: _stamp,
      onSave: (_) async {},
    ),
  );

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  group('the reading surface', () {
    // The direct guard on this change. Playing no longer calls setState, so
    // if the notifier were not wired the word would sit still while the
    // session ran on underneath it — and nothing else in the suite looks at
    // the screen mid-stream.
    testWidgets('advances while playing without a State rebuild', (
      tester,
    ) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Alpha'), findsNothing);

      await disposeTree(tester);
    });
  });

  group('the progress bar', () {
    // The risk the rebuild gate introduces. A gate on the state transition
    // alone would skip this, because a rewind while paused emits without
    // changing state.
    //
    // Driven from the arrow key rather than from a button. ADR 0015 took
    // the rewind button off the reading surface ahead of the left and right
    // tap zones, so the binding is the only rewind a reader has and nothing
    // else in the suite exercises it. That makes this test assert two
    // things at once, which is usually the sign of a bad test; here it is
    // the honest shape, because the button it used to press no longer
    // exists and the behaviour it was checking still does.
    testWidgets('follows a rewind taken while paused', (tester) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byType(RsvpView));
      await tester.pumpAndSettle();

      final afterPause = _progress(tester);

      // `CallbackShortcuts` sits above the Scaffold and resolves upward from
      // whatever holds focus, so the tap on the play button above does not
      // put this out of reach. The settle after `pumpWidget` is what matters:
      // the `Focus(autofocus: true)` node claims focus a frame late, and a
      // key sent before that lands nowhere.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      // Relative rather than a token count. The step is the profile's own
      // `rewindWords`, and a number written here would be a second copy of
      // a value the profile already carries.
      expect(_progress(tester), lessThan(afterPause));

      await disposeTree(tester);
    });

    testWidgets('has caught up by the time playback stops', (tester) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      final atOpen = _progress(tester);

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byType(RsvpView));
      await tester.pumpAndSettle();

      expect(_progress(tester), greaterThan(atOpen));

      await disposeTree(tester);
    });
  });
}
