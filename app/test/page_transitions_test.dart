import 'package:app/theme/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ADR 0034 section 3: the reader route is opaque and does not fade, so it
  // never shares a frame with the route it replaces — the defect #374
  // reported for the shared QuietPageTransitionsBuilder.
  testWidgets(
    'pushing a NoFadePageRoute does not render the previous route\'s subtree',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Text('origin screen'))),
      );

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        NoFadePageRoute<void>(
          builder: (context) => const Scaffold(body: Text('reader route')),
        ),
      );

      // A single pump, not pumpAndSettle: the transition is zero-duration,
      // so the very next frame must already show only the new route.
      await tester.pump();

      expect(find.text('reader route'), findsOneWidget);
      expect(find.text('origin screen'), findsNothing);
    },
  );

  testWidgets('a NoFadePageRoute arrives and leaves without a transition', (
    tester,
  ) async {
    final route = NoFadePageRoute<void>(builder: _emptyBuilder);

    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
  });
}

Widget _emptyBuilder(BuildContext context) => const SizedBox.shrink();
