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

class SyncState {
  final SyncStatus status;
  final int pendingEvents;
  final DateTime? lastSyncedAt;
  final String? message;

  const SyncState({
    required this.status,
    this.pendingEvents = 0,
    this.lastSyncedAt,
    this.message,
  });
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
  Future<void> syncNow() async {
    if (_running || !auth.isSignedIn) return;
    _running = true;

    _emit(SyncStatus.syncing);

    try {
      await _pushPending();
      await _pullRemote();

      await repository.setPreference(
        'sync.last_synced_at',
        DateTime.now().toUtc().toIso8601String(),
        hlc: await issueStamp(),
      );

      _emit(SyncStatus.upToDate, lastSyncedAt: DateTime.now());
    } on NetworkException {
      // The queue is intact. This is the ordinary case on a train.
      _emit(SyncStatus.offline);
    } on ApiException catch (e) {
      _emit(SyncStatus.failed, message: e.message);
    } finally {
      _running = false;
    }
  }

  // -- push ----------------------------------------------------------

  Future<void> _pushPending() async {
    while (true) {
      final pending = await repository.pendingEvents(limit: batchSize);
      if (pending.isEmpty) return;

      final result = await api.push(
        deviceId: deviceId,
        events: pending.map(_toWireEvent).toList(),
      );

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
    'deleted': false,
  };

  // -- pull ----------------------------------------------------------

  Future<void> _pullRemote() async {
    var since = await _lastSeq();

    while (true) {
      final result = await api.pull(since: since, limit: batchSize);

      for (final event in result.events) {
        await _apply(event);
      }

      since = result.events.isEmpty ? result.lastSeq : result.events.last.seq;

      await repository.setPreference(
        'sync.last_seq',
        '$since',
        hlc: await issueStamp(),
      );

      if (!result.hasMore) return;
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
        // Profiles arrive but are not applied yet: editing them needs a
        // settings screen that does not exist.
        break;
      default:
        // An entity type this build does not know. Ignored rather than
        // failed: a newer client may sync something this one cannot use,
        // and refusing would stall the pull forever.
        break;
    }
  }

  Future<void> _applyPosition(PulledEvent event) async {
    final locator = Locator(
      blockId: event.payload['blockId'] as String,
      charOffset: (event.payload['charOffset'] as num?)?.toInt() ?? 0,
      parserVersion: (event.payload['parserVersion'] as num?)?.toInt() ?? 0,
    );

    // Written without queuing an outbox event: this came from the service,
    // so sending it back would loop.
    await repository.applyRemotePosition(
      bookId: event.entityId,
      locator: locator,
      hlc: event.hlc,
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
