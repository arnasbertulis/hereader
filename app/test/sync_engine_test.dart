import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/database.dart' hide PositionConflict;
import 'package:app/data/library_repository.dart';
import 'package:app/sync/api_client.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'fakes.dart';

void main() {
  late AppDatabase database;
  late LibraryRepository repository;
  late FakeSecureStorage storage;
  late AuthStore auth;
  late FakeApi api;
  late SyncEngine sync;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepository(database);

    storage = FakeSecureStorage();
    auth = AuthStore(storage: storage);

    // Signed in, or syncNow returns immediately and every test is vacuous.
    await auth.save(
      const Session(accessToken: 'access', refreshToken: 'refresh'),
    );

    api = FakeApi(auth: auth);
    sync = SyncEngine(
      repository: repository,
      api: api,
      auth: auth,
      database: database,
    );

    await sync.start();
  });

  tearDown(() async {
    sync.dispose();
    auth.dispose();
    await database.close();
  });

  /// A book has to exist before a position can reference it: the foreign key
  /// on reading_positions is enforced.
  Future<void> addBook(String id) => repository.addBook(
    id: id,
    title: 'A Book',
    bytes: Uint8List.fromList([1]),
    wordCount: 1000,
    sourceFormat: 'epub',
  );

  Future<void> savePosition(String bookId, {int tokenIndex = 100}) async {
    await repository.savePosition(
      bookId: bookId,
      locator: Locator(
        blockId: 'block-$tokenIndex',
        charOffset: 0,
        parserVersion: 1,
      ),
      hlc: await sync.issueStamp(),
      tokenIndex: tokenIndex,
    );
  }

  group('clock stamps', () {
    test('are monotonic across issues', () async {
      final stamps = <String>[];
      for (var i = 0; i < 10; i++) {
        stamps.add(await sync.issueStamp());
      }

      final sorted = [...stamps]..sort();
      expect(stamps, equals(sorted));
      expect(stamps.toSet().length, stamps.length);
    });

    test('are persisted as they are issued', () async {
      // A crash between issuing and sending must not let the next stamp
      // repeat one already used.
      final issued = await sync.issueStamp();

      expect(await repository.preference('sync.last_hlc'), issued);
    });

    test('survive a restart', () async {
      final before = HlcStamp.parse(await sync.issueStamp());

      final restarted = SyncEngine(
        repository: repository,
        api: api,
        auth: auth,
        database: database,
      );
      await restarted.start();
      addTearDown(restarted.dispose);

      final after = HlcStamp.parse(await restarted.issueStamp());
      expect(after.compareTo(before), greaterThan(0));
    });

    test('carry this device', () async {
      final stamp = HlcStamp.parse(await sync.issueStamp());

      expect(stamp.deviceId, sync.deviceId);
      expect(stamp.deviceId, isNotEmpty);
    });
  });

  group('pushing', () {
    test('sends what the outbox holds', () async {
      await addBook('book-1');
      await savePosition('book-1', tokenIndex: 250);

      await sync.syncNow();

      expect(api.pushed, hasLength(1));
      expect(api.pushed.single, hasLength(1));

      final event = api.pushed.single.single;
      expect(event['entityType'], 'POSITION');
      expect(event['entityId'], 'book-1');
      expect(event['payload']['tokenIndex'], 250);
    });

    test('clears the outbox once sent', () async {
      await addBook('book-1');
      await savePosition('book-1');

      await sync.syncNow();

      expect(await repository.pendingEvents(), isEmpty);
    });

    test('sends nothing when there is nothing queued', () async {
      await sync.syncNow();

      expect(api.pushed, isEmpty);
    });

    test('clears events the service reports as duplicates', () async {
      await addBook('book-1');
      await savePosition('book-1');

      final pending = await repository.pendingEvents();
      api.pushResponses.add(
        PushResult(
          lastSeq: 1,
          accepted: 0,
          // An earlier response was lost and this client retried. The event
          // is already applied there, so leaving it queued would retry it
          // forever.
          duplicates: [pending.single.idempotencyKey],
          conflicts: const [],
        ),
      );

      await sync.syncNow();

      expect(await repository.pendingEvents(), isEmpty);
    });

    test('leaves the queue intact when the network is unreachable', () async {
      await addBook('book-1');
      await savePosition('book-1');

      api.nextError = const NetworkException('offline');

      await sync.syncNow();

      // The ordinary case on a train. Nothing is lost.
      expect(await repository.pendingEvents(), hasLength(1));
    });

    test('counts an attempt when the service refuses a batch', () async {
      await addBook('book-1');
      await savePosition('book-1');

      api.nextError = const ApiException(400, 'Malformed clock stamp');

      await sync.syncNow();

      final pending = await repository.pendingEvents();
      expect(pending.single.attempts, 1);
    });

    test('parks an event the service will never accept', () async {
      await addBook('book-1');
      await savePosition('book-1');

      // Five refusals is the limit, after which the event stops blocking
      // everything queued behind it.
      for (var i = 0; i < 5; i++) {
        api.nextError = const ApiException(400, 'Malformed clock stamp');
        await sync.syncNow();
      }

      expect(
        await repository.pendingEvents(),
        isEmpty,
        reason: 'parked, not sent',
      );
    });
  });

  group('pulling', () {
    test('asks from the sequence it last saw', () async {
      api.pullResponses.add(
        const PullResult(events: [], lastSeq: 42, hasMore: false),
      );
      await sync.syncNow();

      await sync.syncNow();

      expect(api.pulledSince, [0, 42]);
    });

    test('applies a position from another device', () async {
      await addBook('book-1');

      api.pullResponses.add(
        PullResult(
          events: [
            PulledEvent(
              seq: 1,
              entityType: 'POSITION',
              entityId: 'book-1',
              payload: const {
                'blockId': 'remote-block',
                'charOffset': 12,
                'parserVersion': 1,
                'tokenIndex': 900,
              },
              hlc: '9999999999999-00000-phone',
              deviceId: 'phone',
              deleted: false,
            ),
          ],
          lastSeq: 1,
          hasMore: false,
        ),
      );

      await sync.syncNow();

      final position = await repository.positionOf('book-1');
      expect(position?.blockId, 'remote-block');
      expect(position?.charOffset, 12);
    });

    test(
      'does not queue an applied remote write back to the service',
      () async {
        await addBook('book-1');

        api.pullResponses.add(
          PullResult(
            events: [
              PulledEvent(
                seq: 1,
                entityType: 'POSITION',
                entityId: 'book-1',
                payload: const {
                  'blockId': 'remote-block',
                  'charOffset': 0,
                  'parserVersion': 1,
                },
                hlc: '9999999999999-00000-phone',
                deviceId: 'phone',
                deleted: false,
              ),
            ],
            lastSeq: 1,
            hasMore: false,
          ),
        );

        await sync.syncNow();

        // Sending it back would loop, with each round trip producing another
        // event. Only the sync bookkeeping preferences may be queued.
        final queued = await repository.pendingEvents();
        expect(queued.where((e) => e.entityType == 'position'), isEmpty);
      },
    );

    test('ignores an echo of this device own write', () async {
      await addBook('book-1');
      await savePosition('book-1', tokenIndex: 500);
      await sync.syncNow();

      final before = await repository.positionOf('book-1');

      api.pullResponses.add(
        PullResult(
          events: [
            PulledEvent(
              seq: 1,
              entityType: 'POSITION',
              entityId: 'book-1',
              payload: const {
                'blockId': 'stale',
                'charOffset': 0,
                'parserVersion': 1,
              },
              hlc: '0000000000001-00000-${'x'}',
              deviceId: sync.deviceId,
              deleted: false,
            ),
          ],
          lastSeq: 1,
          hasMore: false,
        ),
      );

      await sync.syncNow();

      expect((await repository.positionOf('book-1'))?.blockId, before?.blockId);
    });

    test('an older remote write does not move the reader backwards', () async {
      await addBook('book-1');
      await savePosition('book-1', tokenIndex: 500);
      await sync.syncNow();

      final current = await repository.positionOf('book-1');

      api.pullResponses.add(
        PullResult(
          events: [
            PulledEvent(
              seq: 2,
              entityType: 'POSITION',
              entityId: 'book-1',
              payload: const {
                'blockId': 'ancient',
                'charOffset': 0,
                'parserVersion': 1,
              },
              // Long before anything this device wrote.
              hlc: '0000000000001-00000-phone',
              deviceId: 'phone',
              deleted: false,
            ),
          ],
          lastSeq: 2,
          hasMore: false,
        ),
      );

      await sync.syncNow();

      expect(
        (await repository.positionOf('book-1'))?.blockId,
        current?.blockId,
      );
    });

    test('an unknown entity type does not stall the pull', () async {
      // A newer client may sync something this build cannot use. Refusing
      // would stall every later event behind it.
      api.pullResponses.add(
        PullResult(
          events: [
            const PulledEvent(
              seq: 1,
              entityType: 'SOMETHING_NEW',
              entityId: 'x',
              payload: {},
              hlc: '9999999999999-00000-phone',
              deviceId: 'phone',
              deleted: false,
            ),
          ],
          lastSeq: 1,
          hasMore: false,
        ),
      );

      await expectLater(sync.syncNow(), completes);
    });
  });

  group('conflicts', () {
    final conflict = PositionConflict(
      id: 7,
      bookId: 'book-1',
      ours: const {
        'blockId': 'ours',
        'charOffset': 0,
        'parserVersion': 1,
        'tokenIndex': 100,
      },
      theirs: const {
        'blockId': 'theirs',
        'charOffset': 0,
        'parserVersion': 1,
        'tokenIndex': 5000,
      },
    );

    test('are fetched even when there is nothing to push', () async {
      // The device that needs to know is the one that has been idle: the
      // reader put down another device and picked this one up.
      api.pendingConflicts = [conflict];

      await sync.syncNow();

      expect(api.pushed, isEmpty);
      expect(api.conflictFetches, 1);

      final stored = await repository.watchConflicts().first;
      expect(stored, hasLength(1));
      expect(stored.single.bookId, 'book-1');
    });

    test('are stored whole so the app can show both candidates', () async {
      api.pendingConflicts = [conflict];
      await sync.syncNow();

      final stored = (await repository.watchConflicts().first).single;

      expect(jsonDecode(stored.oursJson)['tokenIndex'], 100);
      expect(jsonDecode(stored.theirsJson)['tokenIndex'], 5000);
    });

    test('recording the same conflict twice does not ask twice', () async {
      api.pendingConflicts = [conflict];

      await sync.syncNow();
      await sync.syncNow();

      expect(await repository.watchConflicts().first, hasLength(1));
    });

    test(
      'resolving writes the chosen position and clears the question',
      () async {
        await addBook('book-1');
        api.pendingConflicts = [conflict];
        await sync.syncNow();

        await sync.resolveConflict(
          serverId: 7,
          bookId: 'book-1',
          chosen: const Locator(
            blockId: 'theirs',
            charOffset: 0,
            parserVersion: 1,
          ),
          tokenIndex: 5000,
        );

        expect(api.resolvedConflicts, 1);
        expect(await repository.watchConflicts().first, isEmpty);
        expect((await repository.positionOf('book-1'))?.blockId, 'theirs');
      },
    );
  });

  group('signed out', () {
    test('does nothing at all', () async {
      await auth.clear();

      await addBook('book-1');
      await savePosition('book-1');

      await sync.syncNow();

      expect(api.pushed, isEmpty);
      expect(api.pulledSince, isEmpty);
      expect(
        await repository.pendingEvents(),
        hasLength(1),
        reason: 'queued for when the reader signs in',
      );
    });
  });

  test('the device id is stable across restarts', () async {
    final first = await auth.deviceId();
    final second = await auth.deviceId();

    expect(second, first);
  });

  test('the fake stores what is written', () async {
    final storage = FakeSecureStorage();
    await storage.write(key: 'k', value: 'v');

    expect(await storage.read(key: 'k'), 'v');
  });
}
