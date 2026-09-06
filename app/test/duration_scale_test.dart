import 'package:app/reading/profile_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('describeDurationScale', () {
    // Zero always reads as switched off, never as merely brief — a pause a
    // reader turned all the way down should not look like a short pause.
    test('names zero Off regardless of the range', () {
      expect(describeDurationScale(0, max: 800), 'Off');
      expect(describeDurationScale(0, max: 2000), 'Off');
    });

    // The comma pause's own range (0-800ms) splits into thirds at ~267/533.
    test('splits a slider into three named thirds', () {
      expect(describeDurationScale(1, max: 800), 'Short');
      expect(describeDurationScale(266, max: 800), 'Short');
      expect(describeDurationScale(267, max: 800), 'Medium');
      expect(describeDurationScale(533, max: 800), 'Medium');
      expect(describeDurationScale(534, max: 800), 'Long');
      expect(describeDurationScale(800, max: 800), 'Long');
    });

    // Two sliders with different ranges name the same fraction the same way,
    // which is the reason this exists instead of a millisecond readout: 1000
    // is "Medium" on the 1500ms sentence pause and "Long" on the 800ms comma
    // pause, because it means something different on each.
    test('scales relative to each slider\'s own range', () {
      expect(describeDurationScale(1000, max: 1500), 'Medium');
      expect(describeDurationScale(1000, max: 800), 'Long');
    });
  });
}
