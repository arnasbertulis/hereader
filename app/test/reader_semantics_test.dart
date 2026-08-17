import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/reader_screen.dart';
import 'package:app/reading/rsvp_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

Future<String> _stamp() async => '0000000000001-00000-test';

TokenizedText _text() => TokenizedText.from(const [
  (id: 'one', text: 'Alpha beta gamma delta epsilon zeta eta theta.'),
  (id: 'two', text: 'Iota kappa lambda mu nu xi omicron pi.'),
], parserVersion: 1);

void main() {
  late AppDatabase database;
  late TokenizedText text;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    text = _text();
  });

  tearDown(() => database.close());

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
    // The gap this file exists for. The surface is the app's primary
    // control and was a bare GestureDetector: no role, no label, nothing
    // for a screen reader to find or activate.
    testWidgets('is a button a screen reader can find and press', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(RsvpView)),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          label: 'Start reading',
          value: 'Alpha',
        ),
      );

      handle.dispose();
      await disposeTree(tester);
    });

    // The deliberate part. A word announced on every advance would arrive
    // four times a second and fight the visual stream it is describing.
    testWidgets('says nothing word by word while playing', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pump(const Duration(seconds: 1));

      expect(
        tester.getSemantics(find.byType(RsvpView)),
        isSemantics(label: 'Pause reading', value: ''),
      );

      handle.dispose();
      await disposeTree(tester);
    });

    // Paused is different: the word on screen is one fact, and the reader
    // asked for it.
    testWidgets('offers the word once the stream stops', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(readerPlayButtonKey));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byType(RsvpView));
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.byType(RsvpView));
      expect(node.label, 'Start reading');
      expect(node.value, isNotEmpty);

      handle.dispose();
      await disposeTree(tester);
    });
  });

  group('the progress bar', () {
    testWidgets('reports where the reader is', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(LinearProgressIndicator)),
        isSemantics(label: 'Progress through the book'),
      );

      handle.dispose();
      await disposeTree(tester);
    });
  });
}
