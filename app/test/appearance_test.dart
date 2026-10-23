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

  group('text size', () {
    test('round-trips', () {
      expect(decodeTextSize(encodeTextSize(1.25)), 1.25);
      expect(decodeTextSize(encodeTextSize(0.85)), 0.85);
      expect(decodeTextSize(encodeTextSize(1.5)), 1.5);
    });

    test(
      'falls back to the default on anything unparseable or out of range',
      () {
        expect(decodeTextSize(null), 1.0);
        expect(decodeTextSize(''), 1.0);
        expect(decodeTextSize('large'), 1.0);
        expect(decodeTextSize('0.5'), 1.0);
        expect(decodeTextSize('3.0'), 1.0);
      },
    );
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
      await first.setTextSize(1.25);

      final second = controller();
      addTearDown(second.dispose);
      await second.restore();

      expect(second.settings.themeMode, ThemeMode.dark);
      expect(second.settings.accent, AppAccents.rust.color);
      expect(second.settings.highContrast, isTrue);
      expect(second.settings.textSize, 1.25);
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

    test('a text size choice notifies and persists', () async {
      final appearance = controller();
      addTearDown(appearance.dispose);

      var notifications = 0;
      appearance.addListener(() => notifications++);

      await appearance.setTextSize(1.15);

      expect(notifications, 1);
      expect(appearance.settings.textSize, 1.15);
      expect(await repo.preference(AppearanceKeys.textSize), '1.15');
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
      await appearance.setTextSize(1.3);

      expect(await repo.pendingEvents(), isEmpty);
    });
  });

  // The web page paints its loading background before the engine that can
  // read the database is up, so the theme choice is copied somewhere the
  // page can read. The database stays the source of truth: these tests pin
  // that the copy follows it and never the other way round.
  group('theme mirror', () {
    late List<String> mirrored;

    AppearanceController mirroring() => AppearanceController(
      repository: repo,
      issueStamp: issueStamp,
      mirrorThemeMode: mirrored.add,
    );

    setUp(() => mirrored = []);

    test('a choice is mirrored as the word that is stored', () async {
      final appearance = mirroring();
      addTearDown(appearance.dispose);

      await appearance.setThemeMode(ThemeMode.light);
      await appearance.setThemeMode(ThemeMode.dark);
      await appearance.setThemeMode(ThemeMode.system);

      expect(mirrored, ['light', 'dark', 'system']);
    });

    test('restoring mirrors the stored choice', () async {
      await repo.setPreference(
        AppearanceKeys.themeMode,
        'light',
        hlc: await issueStamp(),
        sync: false,
      );

      final appearance = mirroring();
      addTearDown(appearance.dispose);
      await appearance.restore();

      expect(mirrored, ['light']);
    });

    test('restoring with nothing stored mirrors system', () async {
      final appearance = mirroring();
      addTearDown(appearance.dispose);
      await appearance.restore();

      expect(mirrored, ['system']);
    });

    test('setting the mode already in force mirrors nothing', () async {
      final appearance = mirroring();
      addTearDown(appearance.dispose);

      await appearance.setThemeMode(ThemeMode.system);

      expect(mirrored, isEmpty);
    });

    test('the other appearance settings do not touch the mirror', () async {
      final appearance = mirroring();
      addTearDown(appearance.dispose);

      await appearance.setAccent(AppAccents.rust.color);
      await appearance.setHighContrast(true);
      await appearance.setTextSize(1.25);

      expect(mirrored, isEmpty);
    });

    test('a write that fails is not mirrored', () async {
      final appearance = AppearanceController(
        repository: repo,
        issueStamp: () => throw StateError('no stamp'),
        mirrorThemeMode: mirrored.add,
      );
      addTearDown(appearance.dispose);

      await expectLater(
        appearance.setThemeMode(ThemeMode.dark),
        throwsStateError,
      );

      expect(mirrored, isEmpty);
    });
  });
}
