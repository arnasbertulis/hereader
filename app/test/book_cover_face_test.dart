import 'package:app/reading/book_cover.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpFace(
    WidgetTester tester, {
    required BookSourceFormat sourceFormat,
    required String title,
    required double width,
  }) => tester.pumpWidget(
    MaterialApp(
      home: BookCoverImage(
        bookId: 'book-1',
        sourceFormat: sourceFormat,
        title: title,
        width: width,
      ),
    ),
  );

  group('the generated face', () {
    testWidgets('an EPUB with no cover shows neither title nor glyph', (
      tester,
    ) async {
      await pumpFace(
        tester,
        sourceFormat: BookSourceFormat.epub,
        title: 'Romeo and Juliet',
        width: 172,
      );

      expect(find.text('Romeo and Juliet'), findsNothing);
      expect(find.byIcon(AppIcons.writeNote), findsNothing);
    });

    testWidgets("above the width threshold, a Note's face shows its title", (
      tester,
    ) async {
      await pumpFace(
        tester,
        sourceFormat: BookSourceFormat.note,
        title: 'Grocery list',
        width: 172,
      );

      expect(find.text('Grocery list'), findsOneWidget);
      expect(find.byIcon(AppIcons.writeNote), findsNothing);
    });

    testWidgets("at or below the width threshold, a Note's face shows a glyph "
        'instead of its title', (tester) async {
      await pumpFace(
        tester,
        sourceFormat: BookSourceFormat.note,
        title: 'Grocery list',
        width: 72,
      );

      expect(find.text('Grocery list'), findsNothing);
      expect(find.byIcon(AppIcons.writeNote), findsOneWidget);
    });
  });
}
