import 'package:app/reading/info_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InfoDot(
            semanticLabel: 'About high contrast',
            explanation:
                'Your device may already ask for high contrast, in which '
                'case the app follows it whether or not this is on.',
          ),
        ),
      ),
    );
  }

  testWidgets('opens a dialog with the explanation on a wide window', (
    tester,
  ) async {
    await pump(tester, const Size(900, 900));

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.text(
        'Your device may already ask for high contrast, in which '
        'case the app follows it whether or not this is on.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('opens a bottom sheet with the explanation on a narrow window', (
    tester,
  ) async {
    await pump(tester, const Size(400, 800));

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.text(
        'Your device may already ask for high contrast, in which '
        'case the app follows it whether or not this is on.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('carries an accessible label naming what it explains', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const Size(900, 900));

    expect(find.bySemanticsLabel('About high contrast'), findsOneWidget);

    handle.dispose();
  });
}
