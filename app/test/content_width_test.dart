import 'package:app/theme/content_width.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ContentWidth caps its child at maxWidth and centres it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContentWidth(
            maxWidth: 400,
            child: SizedBox(width: 2000, height: 10, key: const Key('c')),
          ),
        ),
      ),
    );

    final childSize = tester.getSize(find.byKey(const Key('c')));
    expect(childSize.width, 400);

    final childTopLeft = tester.getTopLeft(find.byKey(const Key('c')));
    // Centred in a 2000-wide parent: (2000 - 400) / 2 = 800.
    expect(childTopLeft.dx, 800);
  });

  testWidgets('ContentWidth leaves a narrower child unconstrained', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContentWidth(
            maxWidth: 720,
            child: SizedBox(width: 300, height: 10, key: const Key('c')),
          ),
        ),
      ),
    );

    final childSize = tester.getSize(find.byKey(const Key('c')));
    expect(childSize.width, 300);
  });
}
