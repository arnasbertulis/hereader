import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../sync/api_client.dart';
import '../sync/last_synced.dart';
import '../sync/sync_engine.dart';
import '../theme/app_icons.dart';
import '../theme/app_tokens.dart';

/// What sync has done, and a way to make it run now.
///
/// Reports rather than configures. There is nothing here to switch off: a
/// reader who does not want sync does not sign in, and one who signed in
/// wants their place to travel.
///
/// No count of what is waiting to be sent. `SyncState` deliberately carries
/// none after the field that always read zero was removed, and the outbox
/// query the repository exposes is limited and skips parked events, so a
/// number taken from it would answer a narrower question than the label on
/// it would claim.
class SyncScreen extends StatefulWidget {
  final LibraryRepository repository;
  final ApiClient api;
  final SyncEngine sync;

  const SyncScreen({
    super.key,
    required this.repository,
    required this.api,
    required this.sync,
  });

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  DateTime? _lastSynced;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The stored time rather than the one on the stream.
  ///
  /// `SyncState.lastSyncedAt` is set on the successful emit and is null on
  /// every other status, so a screen reading only the stream would tell a
  /// reader whose last run failed that they had never synced at all.
  Future<void> _load() async {
    final stored = (await widget.sync.cursor.read()).lastSyncedAt;
    if (!mounted) return;

    setState(() => _lastSynced = stored);
  }

  Future<void> _syncNow() async {
    await widget.sync.syncNow();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signedIn = widget.api.auth.isSignedIn;

    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: StreamBuilder<SyncState>(
        stream: widget.sync.state,
        builder: (context, snapshot) {
          final status = snapshot.data?.status ?? SyncStatus.idle;
          final message = snapshot.data?.message;

          return ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            children: [
              ListTile(
                leading: Icon(_iconFor(status, signedIn)),
                title: Text(_titleFor(status, signedIn)),
                subtitle: Text(
                  signedIn
                      ? describeLastSynced(_lastSynced)
                      : 'Sign in under Account to turn sync on.',
                ),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(message, style: theme.textTheme.bodyMedium),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: FilledButton(
                  onPressed: signedIn && status != SyncStatus.syncing
                      ? _syncNow
                      : null,
                  child: const Text('Sync now'),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  0,
                ),
                child: Text(
                  'Sync carries your place in each book and your reading '
                  'profiles. It does not carry the books themselves: an EPUB '
                  'stays on the device you added it to.\n\n'
                  'Changes you make offline are kept and sent the next time '
                  'the app reaches the service. Sync also runs by itself '
                  'every few minutes while the app is open.\n\n'
                  'When two devices land far apart in the same book, the app '
                  'asks which place to keep rather than picking one.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _iconFor(SyncStatus status, bool signedIn) {
    if (!signedIn) return AppIcons.syncSignedOut;

    return switch (status) {
      SyncStatus.syncing => AppIcons.syncRunning,
      SyncStatus.offline => AppIcons.syncOffline,
      SyncStatus.failed => AppIcons.syncFailed,
      _ => AppIcons.syncIdle,
    };
  }

  String _titleFor(SyncStatus status, bool signedIn) {
    if (!signedIn) return 'Sync is off';

    return switch (status) {
      SyncStatus.syncing => 'Syncing',
      SyncStatus.offline => 'Offline. Changes are queued.',
      SyncStatus.failed => 'Last run did not finish',
      _ => 'Sync is on',
    };
  }
}
