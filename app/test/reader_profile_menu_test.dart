import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/profile_edit_screen.dart';
import 'package:app/reading/profiles_screen.dart';
import 'package:app/reading/reader_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

Future<String> _stamp() async => '0000000000001-00000-test';

TokenizedText _text() => TokenizedText.from(const [
  (id: 'one', text: 'Alpha beta gamma.'),
], parserVersion: 1);

void main() {
  late AppDatabase database;
  late LibraryRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepository(database);
  });

  tearDown(() => database.close());

  Widget reader() => MaterialApp(
    home: ReaderScreen(
      book: LibraryBook(id: 'b', title: 'A Book', text: _text()),
      repository: repository,
      issueStamp: _stamp,
      onSave: (_) async {},
    ),
  );

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> openProfileSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(readerProfileButtonKey));
    await tester.pumpAndSettle();
  }

  group('the reader profile sheet', () {
    testWidgets('lists every profile with an overflow menu', (tester) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await openProfileSheet(tester);

      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('Central field loss'), findsOneWidget);
      // One overflow menu per preset row — five ship in Presets.all.
      expect(find.byType(PopupMenuButton<String>), findsNWidgets(5));

      await disposeTree(tester);
    });

    testWidgets('carries a row to the full profiles screen', (tester) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await openProfileSheet(tester);

      // The row sits below five preset rows, past what the sheet's lazy
      // list builds without a nudge.
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reading profiles'));
      await tester.pumpAndSettle();

      expect(find.byType(ProfilesScreen), findsOneWidget);
      // The reader is still underneath, ready on return — offstage while
      // covered, which is also why the finder needs telling to look.
      expect(find.byType(ReaderScreen, skipOffstage: false), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('has no delete option on a preset', (tester) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await openProfileSheet(tester);

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();

      expect(find.text('View settings'), findsOneWidget);
      expect(find.text('Make a copy'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);

      await disposeTree(tester);
    });

    testWidgets('copying a preset from the sheet selects the copy', (
      tester,
    ) async {
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await openProfileSheet(tester);

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Make a copy'));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileEditScreen), findsOneWidget);

      final mine = (await repository.allProfiles())
          .where((p) => !p.isBuiltIn)
          .toList();
      expect(mine, hasLength(1));
      expect((await repository.activeProfile()).id, mine.single.id);

      await disposeTree(tester);
    });
  });
}
