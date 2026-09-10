import 'package:app/reading/section_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    "renders at titleLarge — the Section header role, distinct from Row "
    "label's titleMedium and never titleSmall",
    (tester) async {
      late TextTheme textTheme;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              textTheme = Theme.of(context).textTheme;
              return const Scaffold(body: SectionHeader('Presets'));
            },
          ),
        ),
      );

      final style = tester.widget<Text>(find.byType(Text)).style;

      // Issue #346: drifted copies fell back to titleSmall (14px w500) or
      // added onSurfaceVariant dimming on top of titleMedium, making the
      // header smaller/dimmer than the rows it heads. ADR 0031 settles the
      // consolidated widget on titleLarge — the Section header role, given
      // its own size rather than sharing titleMedium with Row label.
      expect(style?.fontSize, textTheme.titleLarge?.fontSize);
      expect(style?.fontWeight, textTheme.titleLarge?.fontWeight);
      expect(style?.color, textTheme.titleLarge?.color);
      expect(style?.fontSize, isNot(textTheme.titleMedium?.fontSize));
      expect(style?.fontSize, isNot(textTheme.titleSmall?.fontSize));
    },
  );

  testWidgets('marks itself as a semantics header', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SectionHeader('Presets'))),
    );

    expect(
      tester.getSemantics(find.text('Presets')),
      matchesSemantics(label: 'Presets', isHeader: true),
    );
  });

  testWidgets('renders the info widget beside the title when given', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SectionHeader('Contrast', info: Icon(Icons.info))),
      ),
    );

    expect(find.text('Contrast'), findsOneWidget);
    expect(find.byIcon(Icons.info), findsOneWidget);
  });

  // ADR 0036: a section carries its header and at most one supporting
  // sentence, taken as a String for the same reason ControlRow's is — a
  // second sentence is then a compile-time impossibility.
  testWidgets('renders no second Text when supportingText is omitted', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SectionHeader('Presets'))),
    );

    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('renders the supporting sentence below the title', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionHeader(
            'Presets',
            supportingText: 'Starting points that ship with the app.',
          ),
        ),
      ),
    );

    expect(find.text('Presets'), findsOneWidget);
    expect(
      find.text('Starting points that ship with the app.'),
      findsOneWidget,
    );
  });

  testWidgets('the supporting sentence never truncates at text scale 2.0', (
    tester,
  ) async {
    const sentence =
        'A sentence long enough to wrap onto more than one line once the '
        'text scale grows.';

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: const Scaffold(
            body: SectionHeader('Presets', supportingText: sentence),
          ),
        ),
      ),
    );

    final supporting = tester.widget<Text>(find.text(sentence));

    expect(supporting.maxLines, isNull);
    expect(supporting.overflow, isNot(TextOverflow.ellipsis));
  });
}
