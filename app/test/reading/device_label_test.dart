import 'package:app/reading/device_label.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('devicePlatformLabel', () {
    test('names Windows on desktop', () {
      expect(
        devicePlatformLabel(platform: TargetPlatform.windows, isWeb: false),
        'Windows',
      );
    });

    test('names Android on desktop', () {
      expect(
        devicePlatformLabel(platform: TargetPlatform.android, isWeb: false),
        'Android',
      );
    });

    test('names iPhone or iPad for iOS', () {
      expect(
        devicePlatformLabel(platform: TargetPlatform.iOS, isWeb: false),
        'iPhone or iPad',
      );
    });

    test('appends "(browser)" when running on the web', () {
      expect(
        devicePlatformLabel(platform: TargetPlatform.windows, isWeb: true),
        'Windows (browser)',
      );
    });

    test('falls back to defaultTargetPlatform when none is given', () {
      expect(
        devicePlatformLabel(isWeb: false),
        devicePlatformLabel(platform: defaultTargetPlatform, isWeb: false),
      );
    });
  });
}
