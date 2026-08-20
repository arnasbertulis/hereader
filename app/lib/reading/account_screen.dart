import 'dart:async';

import 'package:flutter/material.dart';

import '../sync/api_client.dart';
import '../sync/auth_store.dart';
import '../sync/sign_in_screen.dart';
import '../sync/sync_engine.dart';
import '../theme/app_icons.dart';
import '../theme/app_tokens.dart';

/// The session, the device, and the way in and out of an account.
///
/// Signing out is the only destructive thing here, and it is not as
/// destructive as it sounds: books and places are on this device and stay
/// there. The dialog says so, because a reader who thinks otherwise will not
/// press the button and will keep a session they wanted to end.
///
/// No delete-account row. The service exposes no endpoint for it, and a row
/// that opens a mail client to ask someone to do it by hand is worse than
/// the absence.
class AccountScreen extends StatelessWidget {
  final ApiClient api;
  final SyncEngine sync;

  const AccountScreen({super.key, required this.api, required this.sync});

  Future<void> _signIn(BuildContext context) async {
    final signedIn = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => SignInScreen(api: api)));

    if (signedIn == true) unawaited(sync.syncNow());
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your books and your place in them stay on this device. Anything '
          'waiting to sync stays queued until you sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed == true) await api.auth.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: StreamBuilder<Session?>(
        stream: api.auth.sessions,
        initialData: api.auth.current,
        builder: (context, snapshot) {
          final signedIn = snapshot.data != null;

          return ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            children: [
              ListTile(
                leading: Icon(
                  signedIn
                      ? AppIcons.accountSignedIn
                      : AppIcons.accountSignedOut,
                ),
                title: Text(signedIn ? 'Signed in' : 'Not signed in'),
                // No address. AuthStore holds tokens and a device id and
                // nothing else, and naming the account from anything else
                // here would be a guess printed as a fact.
                subtitle: Text(
                  signedIn
                      ? 'Your places and profiles reach your other devices.'
                      : 'Reading works without an account. Sign in to carry '
                            'your place between devices.',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: signedIn
                    ? OutlinedButton(
                        onPressed: () => _signOut(context),
                        child: const Text('Sign out'),
                      )
                    : FilledButton(
                        onPressed: () => _signIn(context),
                        child: const Text('Sign in'),
                      ),
              ),
              const Divider(),
              FutureBuilder<String>(
                future: api.auth.deviceId(),
                builder: (context, id) => ListTile(
                  leading: const Icon(AppIcons.device),
                  title: const Text('This device'),
                  subtitle: Text(id.data ?? 'Reading'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  0,
                ),
                child: Text(
                  'The device name is generated here and stored on this '
                  'device. It goes into every change this device sends, so '
                  'the service can tell your devices apart without knowing '
                  'anything about them.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
