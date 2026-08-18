import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

String stamp(int millis, {int counter = 0, String device = 'test-device'}) =>
    HlcStamp(millis: millis, counter: counter, deviceId: device).toString();

void main() {
  late AppDatabase db;
  late LibraryRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = LibraryRepository(db);
  });

  tearDown(() => db.close());

  ReadingProfile fork({String name = 'Mine'}) =>
      Presets.standard.fork(id: ReadingProfile.newId(), name: name);

  group('active profile', () {
    test('defaults to Standard before the reader has chosen', () async {
      expect((await repo.activeProfile()).id, Presets.standard.id);
    });

    test('remembers a preset', () async {
      await repo.setActiveProfile(Presets.centralFieldLoss.id, hlc: stamp(1));

      expect((await repo.activeProfile()).id, Presets.centralFieldLoss.id);
    });

    test(
      'remembers one of the reader own profiles, with its settings',
      () async {
        final profile = fork(
          name: 'Mine',
        ).copyWith(pacing: const PacingConfig(baseWpm: 123));
        await repo.saveProfile(profile, hlc: stamp(1));

        await repo.setActiveProfile(profile.id, hlc: stamp(2));

        final active = await repo.activeProfile();
        expect(active.id, profile.id);
        expect(active.pacing.baseWpm, 123);
      },
    );

    test('never enqueues, so the pointer stays on this device', () async {
      await repo.setActiveProfile(Presets.spacedType.id, hlc: stamp(1));

      expect(await repo.pendingEvents(), isEmpty);
    });

    test('falls back to Standard when the profile was deleted here', () async {
      final profile = fork();
      await repo.saveProfile(profile, hlc: stamp(1));
      await repo.setActiveProfile(profile.id, hlc: stamp(2));

      await repo.deleteProfile(profile.id, hlc: stamp(3));

      expect((await repo.activeProfile()).id, Presets.standard.id);
    });

    test('falls back when another device deleted the profile', () async {
      // The tombstone arrives through sync rather than through deleteProfile,
      // so nothing local had a chance to clear the pointer at the time.
      final profile = fork();
      await repo.saveProfile(profile, hlc: stamp(1));
      await repo.setActiveProfile(profile.id, hlc: stamp(2));

      await repo.applyRemoteProfile(
        profile: profile,
        hlc: stamp(5),
        deleted: true,
      );

      expect((await repo.activeProfile()).id, Presets.standard.id);
    });

    test('clears a pointer at a preset this build does not have', () async {
      // The built-in namespace is answered from Presets rather than from the
      // database, so a pointer inside it that names nothing is a separate
      // path from a stored id that names nothing. A preset renamed or
      // dropped between builds lands here.
      await repo.setPreference(
        LibraryRepository.activeProfileKey,
        '${ReadingProfile.builtInIdPrefix}withdrawn',
        hlc: stamp(1),
      );

      expect((await repo.activeProfile()).id, Presets.standard.id);
      expect(await repo.preference(LibraryRepository.activeProfileKey), isNull);
    });

    test('clears a pointer that no longer resolves', () async {
      await repo.setPreference(
        LibraryRepository.activeProfileKey,
        'p.never.existed',
        hlc: stamp(1),
      );

      await repo.activeProfile();

      // Left in place it would be re-read and re-rejected on every open.
      expect(await repo.preference(LibraryRepository.activeProfileKey), isNull);
    });

    test(
      'a deleted profile does not drag the pointer off a different one',
      () async {
        final kept = fork(name: 'Kept');
        final gone = fork(name: 'Gone');
        await repo.saveProfile(kept, hlc: stamp(1));
        await repo.saveProfile(gone, hlc: stamp(2));
        await repo.setActiveProfile(kept.id, hlc: stamp(3));

        await repo.deleteProfile(gone.id, hlc: stamp(4));

        expect((await repo.activeProfile()).id, kept.id);
      },
    );
  });

  group('setPreference', () {
    test('is device-local unless asked otherwise', () async {
      await repo.setPreference('theme', 'dark', hlc: stamp(1));

      expect(await repo.preference('theme'), 'dark');
      expect(await repo.pendingEvents(), isEmpty);
    });

    test('enqueues when sync is requested', () async {
      await repo.setPreference('theme', 'dark', hlc: stamp(1), sync: true);

      final queued = await repo.pendingEvents();
      expect(queued, hasLength(1));
      expect(queued.single.entityType, 'preference');
      expect(queued.single.entityId, 'theme');
      expect(queued.single.deleted, isFalse);
    });

    test('sync bookkeeping keys stay put', () async {
      // These are the ones that must never travel: another device applying
      // this device's last_seq would skip events it had never pulled.
      await repo.setPreference('sync.last_seq', '42', hlc: stamp(1));
      await repo.setPreference('sync.last_hlc', stamp(1), hlc: stamp(1));

      expect(await repo.pendingEvents(), isEmpty);
    });
  });

  group('PacingConfig.copyWith', () {
    test('changes one field and carries the rest across', () {
      const original = PacingConfig(
        kind: PacingModelKind.lengthScaled,
        baseWpm: 180,
        lengthScaleStrength: 0.4,
        sentencePause: Duration(milliseconds: 320),
      );

      final changed = original.copyWith(baseWpm: 200);

      expect(changed.baseWpm, 200);
      expect(changed.kind, PacingModelKind.lengthScaled);
      expect(changed.lengthScaleStrength, 0.4);
      expect(changed.sentencePause, const Duration(milliseconds: 320));
    });
  });
}
