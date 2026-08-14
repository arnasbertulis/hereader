import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/profile_presentation.dart';
import 'package:app/reading/reader_screen.dart';
import 'package:drift/native.dart';
import 'package:epub_reader/epub_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

Future<String> _stamp() async => '0000000000001-00000-test';

TokenizedText _text() => TokenizedText.from(const [
  (id: 'one', text: 'Alpha beta gamma.'),
], parserVersion: 1);

void main() {
  group('chrome brightness', () {
    test('a light surface takes light chrome', () {
      expect(chromeBrightnessFor(const PresentationConfig()), Brightness.light);
    });

    test('a dark surface takes dark chrome', () {
      expect(
        chromeBrightnessFor(
          const PresentationConfig(polarity: Polarity.lightOnDark),
        ),
        Brightness.dark,
      );
    });

    // The reason this reads luminance rather than Polarity. A reader can
    // tint the background to anything; the contrast readout warns and
    // deliberately lets them. Polarity decides the ink, which stays dark
    // here, but the chrome sits on the surface and has to be legible
    // against it regardless of what the ink is doing.
    test('a dark tint takes dark chrome even under darkOnLight', () {
      expect(
        chromeBrightnessFor(
          PresentationConfig(tintArgb: argbFrom(0x0A, 0x0A, 0x0A)),
        ),
        Brightness.dark,
      );
    });

    test('the threshold sits where black and white contrast equally', () {
      // Either side of 0.179, so a change to the constant fails here rather
      // than only showing up as chrome that is hard to read.
      final light = argbFrom(0xBB, 0xBB, 0xBB);
      final dark = argbFrom(0x66, 0x66, 0x66);

      expect(relativeLuminance(light), greaterThan(0.179));
      expect(relativeLuminance(dark), lessThan(0.179));
    });
  });

  group('the reader screen', () {
    late AppDatabase database;

    setUp(() => database = AppDatabase(NativeDatabase.memory()));
    tearDown(() => database.close());

    Widget reader(LibraryRepository repo) => MaterialApp(
      theme: appTheme(Brightness.light),
      home: ReaderScreen(
        book: LibraryBook(
          id: 'b',
          title: 'A Book',
          text: _text(),
          contentStartIndex: 0,
          contentStartReason: ContentStartReason.none,
        ),
        repository: repo,
        issueStamp: _stamp,
        onSave: (_) async {},
      ),
    );

    Future<void> disposeTree(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    }

    // The regression this file exists for. Both central field loss presets
    // are lightOnDark, and the controls, the chapter button, the progress
    // bar and the front matter offer are all stacked on the reading surface.
    // Under the app's theme alone they rendered light over near-black.
    testWidgets('takes dark chrome for a lightOnDark profile', (tester) async {
      final repo = LibraryRepository(database);
      await repo.setActiveProfile(Presets.centralFieldLoss.id, hlc: '1');

      await tester.pumpWidget(reader(repo));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Scaffold));
      expect(Theme.of(context).brightness, Brightness.dark);

      await disposeTree(tester);
    });

    // The other half: it follows the profile rather than being hardcoded.
    testWidgets('takes light chrome for a darkOnLight profile', (tester) async {
      final repo = LibraryRepository(database);
      await repo.setActiveProfile(Presets.standard.id, hlc: '1');

      await tester.pumpWidget(reader(repo));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Scaffold));
      expect(Theme.of(context).brightness, Brightness.light);

      await disposeTree(tester);
    });
  });
}
