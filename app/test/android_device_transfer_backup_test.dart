// CI never builds the Android APK (see .github/workflows/ci-flutter.yml),
// so nothing else would catch a future edit dropping the manifest attribute
// or the exclusion rule it points at. Reads the files directly, so this
// suite is VM-only — see schema_migration_test.dart for the same pattern.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'manifest disables cloud backup and points device transfer at exclusion rules',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('android:allowBackup="false"'));
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
    },
  );

  test('device transfer excludes the private data root', () {
    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();

    expect(rules, contains('<device-transfer>'));
    expect(rules, contains('<exclude domain="root" path="."/>'));
  });
}
