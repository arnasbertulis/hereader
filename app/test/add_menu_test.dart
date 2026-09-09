import 'package:app/reading/add_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// #362: the menu used to stack icon-over-title-over-description in a
/// centred column, running ~165px per option — 660px for four, with the
/// fourth cut off below the fold at common phone heights, and centred body
/// text that made every wrapped line start at a different x. These tests
/// pin the fix: rows are left-aligned and short enough that all four fit
/// on screen at the issue's own repro size.
void main() {
  Future<void> pumpMenu(WidgetTester tester, Size surfaceSize) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: AddMenu())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'all four options are on screen at the issue repro size (502x750)',
    (tester) async {
      await pumpMenu(tester, const Size(502, 750));

      for (final key in [
        addMenuFreeBooksKey,
        addMenuEpubKey,
        addMenuNoteKey,
        addMenuPasteKey,
      ]) {
        final finder = find.byKey(key);
        expect(finder, findsOneWidget, reason: '$key should be laid out');
        final rect = tester.getRect(finder);
        expect(
          rect.bottom,
          lessThanOrEqualTo(750),
          reason: '$key should not fall below the fold',
        );
      }
    },
  );

  testWidgets('option titles and descriptions are left-aligned, not centred', (
    tester,
  ) async {
    await pumpMenu(tester, const Size(502, 900));

    final texts = tester.widgetList<Text>(
      find.descendant(of: find.byType(AddMenu), matching: find.byType(Text)),
    );

    expect(texts, isNotEmpty);
    for (final text in texts) {
      expect(
        text.textAlign,
        isNot(TextAlign.center),
        reason: '"${text.data}" should not be centre-aligned',
      );
    }
  });

  testWidgets(
    'the library fact is not repeated across every option that stays in the library',
    (tester) async {
      await pumpMenu(tester, const Size(502, 900));

      final texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(AddMenu),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .whereType<String>();

      final repeatsLibraryFact = texts.where(
        (text) => text.contains('stays in your library'),
      );
      expect(repeatsLibraryFact, isEmpty);
    },
  );

  testWidgets('#431: the menu states what it is for', (tester) async {
    await pumpMenu(tester, const Size(502, 900));

    expect(find.text('Add to your library'), findsOneWidget);
  });

  testWidgets('#431: cancel pops the dialog with no choice', (tester) async {
    AddChoice? result;
    await tester.binding.setSurfaceSize(const Size(502, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<AddChoice>(
                    context: context,
                    builder: (_) => const AddMenu(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(addMenuCancelKey));
    await tester.pumpAndSettle();

    expect(find.byType(AddMenu), findsNothing);
    expect(result, isNull);
  });

  testWidgets(
    '#330: a visible scrollbar hints at the cut-off option when the menu '
    'overflows the viewport',
    (tester) async {
      // 1280x720 with an 0.8 maxHeight cap leaves ~576px, short of the four
      // options' combined height — the issue's own repro size.
      await pumpMenu(tester, const Size(1280, 720));

      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(
        scrollbar.thumbVisibility,
        isTrue,
        reason:
            'the thumb should be visible without a drag to hint at more '
            'content below the fold',
      );
      expect(
        find.byKey(addMenuPasteKey),
        findsOneWidget,
        reason: 'the last option should still be laid out, just scrolled to',
      );
    },
  );
}
