import 'dart:async';

import 'package:app/reading/visible_stream_builder.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<int> controller;

  setUp(() {
    controller = StreamController<int>.broadcast();
  });

  tearDown(() async {
    await controller.close();
  });

  Widget harness({required bool visible}) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: TickerMode(
        enabled: visible,
        child: VisibleStreamBuilder<int>(
          stream: controller.stream,
          builder: (context, snapshot) => Text('${snapshot.data}'),
        ),
      ),
    );
  }

  testWidgets('applies an emission immediately while visible', (tester) async {
    await tester.pumpWidget(harness(visible: true));

    controller.add(1);
    // A broadcast StreamController delivers on a microtask, not
    // synchronously; the first pump only flushes it, the second renders
    // the resulting setState.
    await tester.pump();
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('buffers an emission while hidden and does not rebuild', (
    tester,
  ) async {
    await tester.pumpWidget(harness(visible: false));

    controller.add(1);
    await tester.pump();
    await tester.pump();

    // Nothing applied yet: the tab is hidden, so the emission is buffered
    // rather than rebuilding the widget.
    expect(find.text('1'), findsNothing);
    expect(find.text('null'), findsOneWidget);
  });

  testWidgets(
    'applies the latest buffered emission the frame the tab becomes visible',
    (tester) async {
      final key = GlobalKey();

      Widget wrap({required bool visible}) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: TickerMode(
            enabled: visible,
            child: VisibleStreamBuilder<int>(
              key: key,
              stream: controller.stream,
              builder: (context, snapshot) => Text('${snapshot.data}'),
            ),
          ),
        );
      }

      await tester.pumpWidget(wrap(visible: false));

      controller.add(1);
      await tester.pump();
      await tester.pump();
      expect(find.text('null'), findsOneWidget);

      controller.add(2);
      await tester.pump();
      await tester.pump();
      expect(find.text('null'), findsOneWidget);

      // Becoming visible applies the latest buffered value (2), never the
      // stale intermediate one (1).
      await tester.pumpWidget(wrap(visible: true));
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    },
  );
}
