import 'dart:async';
import 'dart:convert';

import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/database.dart' hide PositionConflict;
import '../data/library_repository.dart';
import 'api_client.dart';
import 'auth_store.dart';

/// What the app shows about sync.
enum SyncStatus {
  /// Signed out, or never run.
  idle,

  syncing,

  /// Everything queued has been sent.
  upToDate,

  /// Could not reach the service. The queue is intact and will be retried.
  offline,

  /// The service refused something, or the session expired.
  failed,
}

/// What the app shows about sync.
///
/// Carries no pending-event count. It used to declare one that `_emit` never
/// set, so anything reading it saw an empty outbox with a hundred events
/// queued — a wrong answer rather than a missing one. Showing how much is
/// waiting is worth doing; it should be added once, on purpose, rather than
/// inherited as a field that already reads zero.
class SyncState {
  final SyncStatus status;
  final DateTime? lastSyncedAt;
  final String? message;

  const SyncState({required this.status, this.lastSyncedAt, this.message});
}

/// Drains the outbox and applies what other devices wrote.
///
/// Nothing here blocks a reader. Sync runs when it can; when it cannot, the
/// outbox keeps its contents and the app carries on exactly as before.
class SyncEngine {
  final LibraryRepository repository;
  final ApiClient api;
  final AuthStore auth;
  final AppDatabase database;

  /// How many events go in one push. Small enough that a failure costs
  /// little, large enough that a month of offline reading does not take
  /// a hundred round trips.
  static const int batchSize = 100;

  /// Where the time of the last finished run is kept.
  ///
  /// Named rather than written as a literal in two files. Settings reads it
  /// to say how long ago sync ran, and `SyncState.lastSyncedAt` cannot
  /// answer that: it is set on the successful emit and null on every other
  /// status, so a device whose last run failed would report never having
  /// synced at all.
  static const String lastSyncedAtKey = 'sync.last_synced_at';

  final _state = StreamController<SyncState>.broadcast();

  HybridLogicalClock? _clock;
  Timer? _periodic;
  bool _running = false;

  SyncEngine({
    required this.repository,
    required this.api,
    required this.auth,
    required this.database,
  });

  Stream<SyncState> get state => _state.stream;

  /// Prepares the clock for this device. Call once at startup.
  ///
  /// Restores the last stamp issued so a restart cannot produce one that
  /// loses to this device's own earlier writes.
  Future<void> start() async {
    final deviceId = await auth.deviceId();
    final clock = HybridLogicalClock(deviceId: deviceId);

    final stored = await repository.preference('sync.last_hlc');
    final last = stored == null ? null : HlcStamp.tryParse(stored);
    if (last != null) clock.restoreFrom(last);

    _clock = clock;

    // Periodic rather than reactive: a reader who pauses mid-chapter has
    // written something worth syncing, and waiting for them to close the
    // book could mean waiting days.
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => syncNow());
  }

  /// A stamp for a write happening now.
  ///
  /// Persisted immediately, so a crash between issuing and sending cannot
  /// let the next stamp repeat this one.
  Future<String> issueStamp() async {
    final clock = _clock;
    if (clock == null) {
      throw StateError('SyncEngine.start() has not been called.');
    }

    final stamp = clock.issue();
    await repository.setPreference(
      'sync.last_hlc',
      stamp.toString(),
      hlc: stamp.toString(),
    );

    return stamp.toString();
  }

  String get deviceId => _clock?.deviceId ?? 'unknown';

  /// Pushes what is queued, then pulls what is new.
  ///
  /// Safe to call at any time. Overlapping calls collapse into one, since a
  /// second drain of the same queue would push events the first is already
  /// sending.
  ///
  /// Never throws. The periodic timer calls this without awaiting, and an
  /// escaping error there is unobservable; worse, an error escaping before
  /// the final [_emit] would leave the indicator claiming work is still
  /// happening. Every exit from here emits a terminal status.
  Future<void> syncNow() async {
    if (_running || !auth.isSignedIn) return;
    _running = true;

    _emit(SyncStatus.syncing);

    try {
      await _pushPending();
      final skipped = await _pullRemote();

      await _recordConflicts(await api.conflicts());

      await repository.setPreference(
        lastSyncedAtKey,
        DateTime.now().toUtc().toIso8601String(),
        hlc: await issueStamp(),
      );

      _emit(
        SyncStatus.upToDate,
        lastSyncedAt: DateTime.now(),
        message: skipped == 0
            ? null
            : '$skipped change${skipped == 1 ? '' : 's'} from another device '
                  'could not be applied and was skipped.',
      );
    } on NetworkException {
      // The queue is intact. This is the ordinary case on a train.
      _emit(SyncStatus.offline);
    } on ApiException catch (e) {
      _emit(SyncStatus.failed, message: e.message);
    } catch (e) {
      // Anything else: a constraint violation, a malformed payload, a bug.
      // Previously these escaped both catch clauses, left the last emitted
      // status at syncing, and the indicator span forever with no work
      // running. A visible failure is worse-looking and more honest.
      _emit(SyncStatus.failed, message: 'Sync could not finish: $e');
    } finally {
      _running = false;
    }
  }

  // -- push ----------------------------------------------------------

  Future<void> _pushPending() async {
    while (true) {
      final pending = await repository.pendingEvents(limit: batchSize);
      if (pending.isEmpty) return;

      final PushResult result;
      try {
        result = await api.push(
          deviceId: deviceId,
          events: pending.map(_toWireEvent).toList(),
        );
      } on ApiException catch (e) {
        // The service refused this batch. Retrying it unchanged will fail
        // the same way, so count the attempt: after enough failures these
        // events are parked and stop blocking everything behind them.
        for (final event in pending) {
          await repository.markFailed(event.id, e.message);
        }
        rethrow;
      }

      // Duplicates are not failures: the service had already seen them, so
      // they are done and should leave the queue with everything else.
      await repository.markSent(pending.map((e) => e.id));

      if (result.conflicts.isNotEmpty) {
        await _recordConflicts(result.conflicts);
      }

      if (pending.length < batchSize) return;
    }
  }

  Map<String, dynamic> _toWireEvent(OutboxEvent event) => {
    'idempotencyKey': event.idempotencyKey,
    'entityType': event.entityType.toUpperCase(),
    'entityId': event.entityId,
    'payload': jsonDecode(event.payloadJson),
    'hlc': event.hlc,
    // Was hardcoded false while nothing could produce a delete. Profiles are
    // the first entity a reader can remove, and ADR 0005 requires the
    // deletion to reach other devices as a tombstone rather than as an
    // absence.
    'deleted': event.deleted,
  };

  // -- pull ----------------------------------------------------------

  /// Applies everything after the last sequence this device saw.
  ///
  /// Returns how many events could not be applied.
  ///
  /// An event that throws is counted and skipped rather than aborting the
  /// run. Stalling instead would be permanent: sync.last_seq is written only
  /// after the batch, so the next attempt pulls the same event, fails the
  /// same way, and the device never advances again. Skipping loses that one
  /// change; stalling loses every change after it.
  Future<int> _pullRemote() async {
    var since = await _lastSeq();
    var skipped = 0;

    while (true) {
      final result = await api.pull(since: since, limit: batchSize);

      for (final event in result.events) {
        try {
          await _apply(event);
        } on NetworkException {
          rethrow;
        } on ApiException {
          rethrow;
        } catch (_) {
          skipped++;
        }
      }

      since = result.events.isEmpty ? result.lastSeq : result.events.last.seq;

      await repository.setPreference(
        'sync.last_seq',
        '$since',
        hlc: await issueStamp(),
      );

      // A service reporting more to come while sending nothing would spin
      // this loop forever, with the indicator running the whole time.
      if (result.events.isEmpty || !result.hasMore) return skipped;
    }
  }

  /// Applies one remote event locally.
  ///
  /// The service has already resolved which write wins, so this does not
  /// re-decide. It does compare stamps for its own device's writes, because
  /// an event this device sent can arrive back after a newer local write.
  Future<void> _apply(PulledEvent event) async {
    // Fold the remote stamp in, so the next stamp this device issues sorts
    // after everything it has seen.
    final remote = HlcStamp.tryParse(event.hlc);
    if (remote != null) _clock?.observe(remote);

    // An echo of this device's own write. Already applied locally.
    if (event.deviceId == deviceId) return;

    switch (event.entityType.toUpperCase()) {
      case 'POSITION':
        await _applyPosition(event);
      case 'PREFERENCE':
        await _applyPreference(event);
      case 'PROFILE':
        await _applyProfile(event);
      default:
        // An entity type this build does not know. Ignored rather than
        // failed: a newer client may sync something this one cannot use,
        // and refusing would stall the pull forever.
        break;
    }
  }

  Future<void> _applyPosition(PulledEvent event) async {
    final blockId = event.payload['blockId'];
    if (blockId is! String) {
      throw FormatException(
        'Position event ${event.seq} carries no blockId.',
        jsonEncode(event.payload),
      );
    }

    final locator = Locator(
      blockId: blockId,
      charOffset: (event.payload['charOffset'] as num?)?.toInt() ?? 0,
      parserVersion: (event.payload['parserVersion'] as num?)?.toInt() ?? 0,
    );

    // Written without queuing an outbox event: this came from the service,
    // so sending it back would loop.
    //
    // The repository decides whether this lands in reading_positions or
    // waits in pending_positions. A device that has not imported this book
    // — every web client on first sign-in — cannot satisfy the foreign key,
    // and the position waits there until the book is imported.
    await repository.applyRemotePosition(
      bookId: event.entityId,
      locator: locator,
      hlc: event.hlc,
      // Optional on the wire. A client older than the column sends a
      // position without one, which is a value this device does not know
      // rather than an event it cannot apply.
      tokenIndex: (event.payload['tokenIndex'] as num?)?.toInt(),
    );
  }

  Future<void> _applyPreference(PulledEvent event) async {
    final value = event.payload['value'];
    if (value is! String) return;

    await repository.applyRemotePreference(
      key: event.entityId,
      value: value,
      hlc: event.hlc,
    );
  }

  /// Writes a profile another device created, edited, or deleted.
  ///
  /// The service keyed and ordered this event by [PulledEvent.entityId], so
  /// that id wins over whatever the payload carries. Everything else about
  /// the profile degrades rather than throwing, because a throw here counts
  /// as a skipped event and sync.last_seq advances past it.
  ///
  /// A payload claiming a built-in id is refused inside the repository:
  /// ReadingProfile derives isBuiltIn from the id, so nothing on the wire can
  /// assert it.
  Future<void> _applyProfile(PulledEvent event) async {
    final profile = ReadingProfile.fromJson({
      ...event.payload,
      'id': event.entityId,
    });

    await repository.applyRemoteProfile(
      profile: profile,
      hlc: event.hlc,
      deleted: event.deleted,
    );
  }

  // -- conflicts -----------------------------------------------------

  Future<void> _recordConflicts(List<PositionConflict> conflicts) async {
    for (final conflict in conflicts) {
      await repository.recordPositionConflict(
        serverId: conflict.id,
        bookId: conflict.bookId,
        ours: jsonEncode(conflict.ours),
        theirs: jsonEncode(conflict.theirs),
      );
    }
  }

  /// Settles a divergence with the position the reader picked.
  Future<void> resolveConflict({
    required int serverId,
    required String bookId,
    required Locator chosen,
    required int tokenIndex,
  }) async {
    final hlc = await issueStamp();

    await api.resolveConflict(
      conflictId: serverId,
      chosen: {...chosen.toJson(), 'tokenIndex': tokenIndex},
      hlc: hlc,
      deviceId: deviceId,
    );

    await repository.applyRemotePosition(
      bookId: bookId,
      locator: chosen,
      hlc: hlc,
      // The reader picked this side, and the index that came with it is the
      // one already going to the service on the line above.
      tokenIndex: tokenIndex,
    );

    await repository.clearPositionConflict(serverId);
  }

  // -- plumbing ------------------------------------------------------

  Future<int> _lastSeq() async {
    final stored = await repository.preference('sync.last_seq');
    return int.tryParse(stored ?? '') ?? 0;
  }

  void _emit(SyncStatus status, {DateTime? lastSyncedAt, String? message}) {
    if (_state.isClosed) return;
    _state.add(
      SyncState(status: status, lastSyncedAt: lastSyncedAt, message: message),
    );
  }

  void dispose() {
    _periodic?.cancel();
    _state.close();
  }
}
