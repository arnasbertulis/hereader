import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/theme/app_colors.dart';
import 'package:app/theme/appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repo;
  late int stamps;

  Future<String> issueStamp() async {
    stamps++;
    return '000000000000$stamps-00000-test';
  }

  AppearanceController controller() =>
      AppearanceController(repository: repo, issueStamp: issueStamp);

  setUp(() {
    db = AppDatabase(testExecutor());
    repo = LibraryRepository(db);
    stamps = 0;
  });

  tearDown(() => db.close());

  group('theme mode', () {
    test('round-trips every case', () {
      for (final mode in ThemeMode.values) {
        expect(decodeThemeMode(encodeThemeMode(mode)), mode);
      }
    });

    // Read inside the try whose catch renders the startup failure screen, so
    // a value this build does not recognise has to produce something
    // renderable rather than a throw.
    test('falls back to the platform on anything unrecognised', () {
      expect(decodeThemeMode(null), ThemeMode.system);
      expect(decodeThemeMode(''), ThemeMode.system);
      expect(decodeThemeMode('2'), ThemeMode.system);
      expect(decodeThemeMode('midnight'), ThemeMode.system);
    });
  });

  group('accent', () {
    test('round-trips every accent on the list', () {
      for (final accent in AppAccents.all) {
        expect(decodeAccent(encodeAccent(accent.color)), accent.color);
      }
    });

    // Stored as a colour rather than a name, so an accent that is not on the
    // list needs no second format and no migration.
    test('round-trips a colour that is not on the list', () {
      const custom = Color(0xFF123456);

      expect(encodeAccent(custom), '#123456');
      expect(decodeAccent('#123456'), custom);
    });

    test('reads a value written without a hash, in either case', () {
      expect(decodeAccent('14746f'), AppAccents.teal.color);
      expect(decodeAccent('#14746F'), AppAccents.teal.color);
    });

    test('falls back to the default on anything unparseable', () {
      final ink = AppAccents.defaultAccent.color;

      expect(decodeAccent(null), ink);
      expect(decodeAccent(''), ink);
      expect(decodeAccent('#12345'), ink);
      expect(decodeAccent('#1234567'), ink);
      expect(decodeAccent('#GGGGGG'), ink);
      // Six characters, and `int.parse` would take the first pair as a
      // negative number rather than refusing it.
      expect(decodeAccent('-14746'), ink);
    });
  });

  group('high contrast', () {
    test('round-trips', () {
      expect(decodeHighContrast(encodeHighContrast(true)), isTrue);
      expect(decodeHighContrast(encodeHighContrast(false)), isFalse);
    });

    test('falls back to off', () {
      expect(decodeHighContrast(null), isFalse);
      expect(decodeHighContrast('yes'), isFalse);
    });
  });

  group('controller', () {
    test('starts from the defaults when nothing is stored', () async {
      final appearance = controller();
      addTearDown(appearance.dispose);

      await appearance.restore();

      expect(appearance.settings, AppearanceSettings.defaults);
      expect(stamps, 0, reason: 'reading should not issue a stamp');
    });

    test('a choice survives a restart', () async {
      final first = controller();
      addTearDown(first.dispose);

      await first.setThemeMode(ThemeMode.dark);
      await first.setAccent(AppAccents.rust.color);
      await first.setHighContrast(true);

      final second = controller();
      addTearDown(second.dispose);
      await second.restore();

      expect(second.settings.themeMode, ThemeMode.dark);
      expect(second.settings.accent, AppAccents.rust.color);
      expect(second.settings.highContrast, isTrue);
    });

    test('writes hex a person can read', () async {
      final appearance = controller();
      addTearDown(appearance.dispose);

      await appearance.setAccent(AppAccents.teal.color);

      expect(await repo.preference(AppearanceKeys.accent), '#14746F');
    });

    test('notifies on a change', () async {
      final appearance = controller();
      addTearDown(appearance.dispose);

      var notifications = 0;
      appearance.addListener(() => notifications++);

      await appearance.setHighContrast(true);

      expect(notifications, 1);
      expect(appearance.settings.highContrast, isTrue);
    });

    // Tapping the row that is already selected is the ordinary case, not an
    // edge one. It should cost nothing: no stamp, no write, no rebuild of
    // every screen in the app.
    test('does nothing when the value has not changed', () async {
      final appearance = controller();
      addTearDown(appearance.dispose);

      await appearance.setAccent(AppAccents.moss.color);
      final after = stamps;

      var notifications = 0;
      appearance.addListener(() => notifications++);
      await appearance.setAccent(AppAccents.moss.color);

      expect(stamps, after);
      expect(notifications, 0);
    });

    // The reason `sync: false` is passed explicitly at every write rather
    // than left to the default: completing the outbound preference path
    // later must not make these start travelling.
    test('queues nothing for other devices', () async {
      final appearance = controller();
      addTearDown(appearance.dispose);

      await appearance.setThemeMode(ThemeMode.light);
      await appearance.setAccent(AppAccents.crimson.color);
      await appearance.setHighContrast(true);

      expect(await repo.pendingEvents(), isEmpty);
    });
  });
}
