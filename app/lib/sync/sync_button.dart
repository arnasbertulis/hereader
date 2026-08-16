import 'package:flutter/material.dart';

import 'api_client.dart';
import 'sync_engine.dart';

/// Sync state in the app bar, and the way in to signing in.
///
/// Deliberately quiet. Sync failing is not the reader's problem to solve
/// mid-chapter, so nothing here interrupts; it reports and gets out of the
/// way.
///
/// Public and outside any screen because two bars show it. It was private to
/// the library while the library was the only screen with a bar; Home has one
/// now, and a second copy would be four states kept in step by hand.
class SyncButton extends StatelessWidget {
  final SyncEngine sync;
  final ApiClient api;
  final VoidCallback onSignIn;

  const SyncButton({
    super.key,
    required this.sync,
    required this.api,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncState>(
      stream: sync.state,
      builder: (context, snapshot) {
        if (!api.auth.isSignedIn) {
          return IconButton(
            onPressed: onSignIn,
            icon: const Icon(Icons.cloud_off_outlined),
            tooltip: 'Sign in to sync',
          );
        }

        final status = snapshot.data?.status ?? SyncStatus.idle;

        return switch (status) {
          SyncStatus.syncing => const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                // Every other arm of this switch is a button with a
                // tooltip. This one replaces the button while a sync runs,
                // so without a label the control disappears from the
                // semantics tree entirely rather than changing state.
                semanticsLabel: 'Syncing',
              ),
            ),
          ),
          SyncStatus.offline => IconButton(
            onPressed: sync.syncNow,
            icon: const Icon(Icons.cloud_off),
            tooltip: 'Offline. Changes are saved and will sync later.',
          ),
          SyncStatus.failed => IconButton(
            onPressed: sync.syncNow,
            icon: Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            tooltip: snapshot.data?.message ?? 'Sync failed. Tap to retry.',
          ),
          _ => IconButton(
            onPressed: sync.syncNow,
            icon: const Icon(Icons.cloud_done_outlined),
            tooltip: 'Synced. Tap to sync now.',
          ),
        };
      },
    );
  }
}
