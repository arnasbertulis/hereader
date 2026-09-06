import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/paste_reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repository;

  setUp(() {
    db = AppDatabase(testExecutor());
    repository = LibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PasteReaderScreen(
          repository: repository,
          issueStamp: () async => '0000000000001-00000-test',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void mockClipboard(String? text) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          if (call.method == 'Clipboard.getData') {
            return text == null ? null : {'text': text};
          }
          return null;
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
    'Paste is the only, obvious control before there is anything to read',
    (tester) async {
      mockClipboard('Copied from another app.');
      await pump(tester);

      // Before there is text, "Read this" is not offered at all — there is
      // nothing to read yet, so it is not the primary action.
      expect(find.widgetWithText(FilledButton, 'Paste'), findsOneWidget);
      expect(find.text('Read this'), findsNothing);

      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();

      expect(find.text('Copied from another app.'), findsOneWidget);
      // Now that there is text, "Read this" takes over as the primary
      // action, and paste becomes secondary rather than disappearing.
      expect(find.widgetWithText(FilledButton, 'Read this'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Paste'), findsOneWidget);
    },
  );

  testWidgets('the field has a visible label, not just a hint', (tester) async {
    await pump(tester);

    expect(find.text('Text to read'), findsOneWidget);
  });
}
