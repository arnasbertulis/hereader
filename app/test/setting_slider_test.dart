import 'package:app/reading/setting_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool enabled}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingSlider(
            label: 'Reading speed',
            valueLabel: '250 wpm',
            value: 250,
            min: 60,
            max: 800,
            enabled: enabled,
            onChanged: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets(
    'a locked slider draws no Slider, but keeps its label and value',
    (tester) async {
      await pump(tester, enabled: false);

      expect(find.byType(Slider), findsNothing);
      expect(find.text('Reading speed'), findsOneWidget);
      expect(find.text('250 wpm'), findsOneWidget);
    },
  );

  testWidgets('an editable slider still draws its Slider', (tester) async {
    await pump(tester, enabled: true);

    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('Reading speed'), findsOneWidget);
    expect(find.text('250 wpm'), findsOneWidget);
  });
}
