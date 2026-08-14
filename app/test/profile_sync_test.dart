import 'dart:convert';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// A stamp for a write at [millis].
///
/// Stamps are fixed-width, so a larger millis always sorts later regardless of
/// the values around it. Tests read better with small numbers than with real
/// epoch milliseconds.
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

  /// Everything the reader would see that is not shipped in code.
  Future<List<ReadingProfile>> stored() async =>
      (await repo.allProfiles()).where((p) => !p.isBuiltIn).toList();

  ReadingProfile fork({String name = 'Mine'}) =>
      Presets.standard.fork(id: ReadingProfile.newId(), name: name);

  group('saveProfile', () {
    test('stores the profile and queues one event', () async {
      final profile = fork();

      await repo.saveProfile(profile, hlc: stamp(1));

      expect(await stored(), hasLength(1));
      expect((await stored()).single.name, 'Mine');

      final queued = await repo.pendingEvents();
      expect(queued, hasLength(1));
      expect(queued.single.entityType, 'profile');
      expect(queued.single.entityId, profile.id);
      expect(queued.single.deleted, isFalse);
    });

    test('presets are refused rather than stored', () async {
      // isBuiltIn reads the id namespace, so this covers a preset passed in
      // directly and anything else wearing a preset's id.
      expect(
        () => repo.saveProfile(Presets.standard, hlc: stamp(1)),
        throwsArgumentError,
      );
      expect(await stored(), isEmpty);
    });

    test('a fork cannot keep a preset id', () {
      expect(
        () => Presets.standard.fork(id: 'builtin.something'),
        throwsArgumentError,
      );
    });

    test(
      'editing the same profile replaces it rather than adding one',
      () async {
        final profile = fork(name: 'First');

        await repo.saveProfile(profile, hlc: stamp(1));
        await repo.saveProfile(profile.copyWith(name: 'Second'), hlc: stamp(2));

        expect(await stored(), hasLength(1));
        expect((await stored()).single.name, 'Second');
      },
    );
  });

  group('deleteProfile', () {
    test(
      'tombstones the row and queues a delete carrying the whole profile',
      () async {
        final profile = fork(name: 'Doomed');
        await repo.saveProfile(profile, hlc: stamp(1));

        await repo.deleteProfile(profile.id, hlc: stamp(2));

        expect(await stored(), isEmpty);

        final delete = (await repo.pendingEvents()).last;
        expect(delete.deleted, isTrue);
        expect(delete.entityId, profile.id);

        // The whole profile travels so a device that never received the create
        // can still write a complete tombstone row of its own.
        final payload = jsonDecode(delete.payloadJson) as Map<String, dynamic>;
        expect(payload['name'], 'Doomed');
        expect(payload['pacing'], isA<Map<String, dynamic>>());
        expect(payload['presentation'], isA<Map<String, dynamic>>());
      },
    );

    test('deleting twice queues only one event', () async {
      final profile = fork();
      await repo.saveProfile(profile, hlc: stamp(1));

      await repo.deleteProfile(profile.id, hlc: stamp(2));
      final after = (await repo.pendingEvents()).length;

      await repo.deleteProfile(profile.id, hlc: stamp(3));

      expect((await repo.pendingEvents()).length, after);
    });

    test('deleting something never stored queues nothing', () async {
      await repo.deleteProfile('p.does.not.exist', hlc: stamp(1));
      expect(await repo.pendingEvents(), isEmpty);
    });

    test('presets cannot be deleted', () async {
      expect(
        () => repo.deleteProfile(Presets.standard.id, hlc: stamp(1)),
        throwsArgumentError,
      );
    });
  });

  group('applyRemoteProfile', () {
    test('writes a profile this device has never seen', () async {
      final profile = fork(name: 'From the phone');

      await repo.applyRemoteProfile(
        profile: profile,
        hlc: stamp(1),
        deleted: false,
      );

      expect((await stored()).single.name, 'From the phone');
    });

    test(
      'queues nothing, so the event cannot loop back to the service',
      () async {
        await repo.applyRemoteProfile(
          profile: fork(),
          hlc: stamp(1),
          deleted: false,
        );

        expect(await repo.pendingEvents(), isEmpty);
      },
    );

    test('a newer remote write replaces an older local one', () async {
      final profile = fork(name: 'Local');
      await repo.saveProfile(profile, hlc: stamp(2));

      await repo.applyRemoteProfile(
        profile: profile.copyWith(name: 'Remote'),
        hlc: stamp(5),
        deleted: false,
      );

      expect((await stored()).single.name, 'Remote');
    });

    test('an older remote write loses to a newer local one', () async {
      final profile = fork(name: 'Local');
      await repo.saveProfile(profile, hlc: stamp(5));

      await repo.applyRemoteProfile(
        profile: profile.copyWith(name: 'Remote'),
        hlc: stamp(2),
        deleted: false,
      );

      expect((await stored()).single.name, 'Local');
    });

    test('a remote delete removes a profile stored locally', () async {
      final profile = fork();
      await repo.saveProfile(profile, hlc: stamp(1));

      await repo.applyRemoteProfile(
        profile: profile,
        hlc: stamp(2),
        deleted: true,
      );

      expect(await stored(), isEmpty);
    });

    test(
      'a create arriving after a delete does not resurrect the profile',
      () async {
        // The whole reason the tombstone keeps the row. Without a stamp to lose
        // against, this create would look like the first thing this device had
        // ever heard about the profile.
        final profile = fork();

        await repo.applyRemoteProfile(
          profile: profile,
          hlc: stamp(9),
          deleted: true,
        );
        await repo.applyRemoteProfile(
          profile: profile,
          hlc: stamp(4),
          deleted: false,
        );

        expect(await stored(), isEmpty);
      },
    );

    test('a later create does bring the profile back', () async {
      // A reader who deletes a profile on one device and makes another with
      // the same id would be unusual, but the ordering rule should not care.
      final profile = fork(name: 'Second life');

      await repo.applyRemoteProfile(
        profile: profile,
        hlc: stamp(4),
        deleted: true,
      );
      await repo.applyRemoteProfile(
        profile: profile,
        hlc: stamp(9),
        deleted: false,
      );

      expect((await stored()).single.name, 'Second life');
    });

    test('a profile claiming a preset id is refused', () async {
      await repo.applyRemoteProfile(
        profile: Presets.standard,
        hlc: stamp(1),
        deleted: false,
      );

      // Refused quietly: no stored row, and the preset still appears once
      // rather than twice.
      expect(await stored(), isEmpty);
      expect(
        (await repo.allProfiles()).where((p) => p.id == Presets.standard.id),
        hasLength(1),
      );
    });
  });

  group('watchProfiles', () {
    test('lists presets before the reader own profiles', () async {
      await repo.saveProfile(fork(name: 'Mine'), hlc: stamp(1));

      final all = await repo.allProfiles();

      expect(all.take(Presets.all.length).every((p) => p.isBuiltIn), isTrue);
      expect(all.last.name, 'Mine');
    });

    test('emits again when a profile is saved', () async {
      final seen = <int>[];
      final sub = repo.watchProfiles().listen((p) => seen.add(p.length));

      await repo.saveProfile(fork(), hlc: stamp(1));
      await pumpEventQueue();

      // The settings screen follows this stream, so a save has to reach it
      // without the screen reloading by hand.
      expect(seen, contains(Presets.all.length + 1));
      await sub.cancel();
    });
  });
}
