import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import '../sync/api_client.dart';
import '../sync/auth_store.dart';
import '../sync/last_synced.dart';
import '../sync/sign_in_screen.dart';
import '../sync/sync_engine.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_tokens.dart';
import '../theme/appearance.dart';
import '../theme/content_width.dart';
import 'about_screen.dart';
import 'appearance_screen.dart';
import 'profile_presentation.dart';
import 'profiles_screen.dart';
import 'reading_display.dart';
import 'reading_settings_screen.dart';

/// An index of settings sections, each pushing a subpage.
///
/// This screen was the profile list until now, with an appearance row bolted
/// to the top of it. Six sections in one scroll is a screen the reader has to
/// read to the end of to learn what is on it, and the reader this app is for
/// reads it at a text size that makes the scroll long.
///
/// Every row states its current value. A row that only names a section makes
/// the reader open it to find out whether it was the one they wanted, which
/// costs a push, a read and a back gesture per guess.
class SettingsScreen extends StatefulWidget {
  final LibraryRepository repository;

  /// Supplies a clock stamp for each write. Pass `syncEngine.issueStamp`.
  ///
  /// Injected rather than taking the engine itself: the subpages that write
  /// need a stamp, not a sync engine, and a fake in a test should not have
  /// to be one.
  final Future<String> Function() issueStamp;

  final AppearanceController appearance;

  /// For the Reading row, which now states a value as well as naming a
  /// section.
  final ReadingDisplayController display;

  /// For the account block, which reads the session and runs a sync.
  final ApiClient api;
  final SyncEngine sync;

  const SettingsScreen({
    super.key,
    required this.repository,
    required this.issueStamp,
    required this.appearance,
    required this.display,
    required this.api,
    required this.sync,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ReadingProfile? _activeProfile;
  DateTime? _lastSynced;

  @override
  void initState() {
    super.initState();
    _loadValues();
  }

  /// Reads the two values that are not already on a stream.
  ///
  /// Called again whenever a subpage returns, or a sign-in, sign-out or sync
  /// completes, because a reader who just changed one of these should not
  /// come back to a row still naming the old state.
  Future<void> _loadValues() async {
    // Resolved rather than read raw, so a pointer at a profile deleted on
    // another device names Standard instead of nothing.
    final active = await widget.repository.activeProfile();
    final synced = (await widget.sync.cursor.read()).lastSyncedAt;

    if (!mounted) return;

    setState(() {
      _activeProfile = active;
      _lastSynced = synced;
    });
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => screen));

    await _loadValues();
  }

  Future<void> _signIn(BuildContext context) async {
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SignInScreen(api: widget.api)),
    );

    if (signedIn == true) unawaited(widget.sync.syncNow());
    await _loadValues();
  }

  Future<void> _signOut(BuildContext sheetContext) async {
    final confirmed = await showDialog<bool>(
      context: sheetContext,
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

    if (confirmed != true) return;
    if (!sheetContext.mounted) return;

    Navigator.of(sheetContext).pop();
    await widget.api.logOut();
    await _loadValues();
  }

  /// The small sheet the signed-in account row opens: the account fact and
  /// the one destructive action here. No delete-account row: the service
  /// exposes no endpoint for it, and a row that opens a mail client to ask
  /// someone to do it by hand is worse than the absence.
  Future<void> _openAccountSheet(BuildContext context) async {
    final theme = Theme.of(context);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.bottomSheetTheme.backgroundColor,
      elevation: theme.bottomSheetTheme.elevation,
      shape: theme.bottomSheetTheme.shape,
      builder: (sheetContext) => Theme(
        data: theme,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Signed in', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Your places and profiles reach your other devices.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton(
                  onPressed: () => _signOut(sheetContext),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _syncNow() async {
    await widget.sync.syncNow();
    await _loadValues();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No app bar. Its title repeated the tab label underneath it, the
      // same reasoning already applied to Home and Library.
      body: SafeArea(
        // The shell owns the bottom edge, and its own Scaffold has already
        // taken the inset for the nav bar.
        bottom: false,
        child: ListenableBuilder(
          listenable: widget.appearance,
          builder: (context, _) {
            return StreamBuilder<List<ReadingProfile>>(
              stream: widget.repository.watchProfiles(),
              builder: (context, snapshot) {
                final profiles = snapshot.data ?? const <ReadingProfile>[];

                return ContentWidth(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                    children: [
                      _AccountBlock(
                        api: widget.api,
                        sync: widget.sync,
                        lastSynced: _lastSynced,
                        onSignIn: () => _signIn(context),
                        onOpenAccount: () => _openAccountSheet(context),
                        onSyncNow: _syncNow,
                      ),
                      const Divider(height: AppSpacing.xl),
                      _IndexRow(
                        icon: AppIcons.sectionProfiles,
                        title: 'Reading profiles',
                        value: _profilesValue(profiles),
                        onTap: () => _push(
                          ProfilesScreen(
                            repository: widget.repository,
                            issueStamp: widget.issueStamp,
                          ),
                        ),
                      ),
                      _IndexRow(
                        icon: AppIcons.sectionAppearance,
                        title: 'Appearance',
                        value: describeAppearance(widget.appearance.settings),
                        onTap: () => _push(
                          AppearanceScreen(controller: widget.appearance),
                        ),
                      ),
                      _IndexRow(
                        icon: AppIcons.sectionReading,
                        title: 'Reading',
                        value: describeReading(widget.display.timeLeftScope),
                        onTap: () => _push(
                          ReadingSettingsScreen(display: widget.display),
                        ),
                      ),
                      _IndexRow(
                        icon: AppIcons.sectionAbout,
                        title: 'About',
                        value:
                            'Licence, research, and what this app does not claim',
                        onTap: () => _push(const AboutScreen()),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// The active profile's name, pacing and type size, and how many the
  /// reader has of their own — or `Loading` before the first profile read
  /// resolves.
  ///
  /// Presets are excluded from the count. Five of the profiles in that
  /// stream ship with the app, so counting them all would tell every reader
  /// they have five before they have made one.
  String _profilesValue(List<ReadingProfile> profiles) {
    final active = _activeProfile;

    if (active == null) return 'Loading';

    final mine = profiles.where((p) => !p.isBuiltIn).length;

    return describeActiveProfile(active, mine);
  }
}

/// The active profile's name, pacing and type size, and ownership count, as
/// the settings index states them.
///
/// Pacing and type size are the two settings that most determine how a page
/// reads, and until now reaching them meant a push into this row's own
/// screen, then a row's overflow menu, then Edit. Stating them here does not
/// remove that path — a reader who wants a different profile, or a different
/// value, still opens it the same way — but a reader who only wants to know
/// what is active no longer has to.
String describeActiveProfile(ReadingProfile active, int ownProfileCount) {
  final ownership = ownProfileCount == 0
      ? 'presets only'
      : '$ownProfileCount of your own';
  final pacing = describeProfile(active);
  final size = '${active.presentation.fontSizePt.round()} pt';

  return '${active.name} · $pacing · $size · $ownership';
}

/// The Reading section's one setting, as the index states it.
///
/// The section holds more than this, but the rest is fixed behaviour the
/// reader cannot change, and a row that summarises what it cannot alter tells
/// them nothing about whether to open it.
String describeReading(TimeLeftScope scope) => switch (scope) {
  TimeLeftScope.chapter => 'Time left counts this chapter',
  TimeLeftScope.book => 'Time left counts the whole book',
};

/// The theme and accent, as the settings index states them.
///
/// The accent is named where the reader picked a named one and called custom
/// otherwise, rather than shown as a hex value nobody reads back.
String describeAppearance(AppearanceSettings settings) {
  final mode = switch (settings.themeMode) {
    ThemeMode.system => 'Match my device',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  final named = AppAccents.all
      .where((a) => a.color == settings.accent)
      .firstOrNull;

  final contrast = settings.highContrast ? ' · High contrast' : '';

  return '$mode · ${named?.name ?? 'Custom'}$contrast';
}

/// Are you signed in, and is your reading backed up — one fact and one
/// action, at the top of Settings.
///
/// Replaces the old Account and Sync screens (ADR 0034 §2): a destination
/// whose entire purpose is one control is a row, and this was two of them.
/// Tapping the row itself is the account control: it signs in when signed
/// out and opens a small sheet (account, sign out) when signed in. The
/// trailing icon button is sync: it runs one now, and its icon carries sync's
/// state.
///
/// The state is spelled out in words on the second line rather than left to
/// the icon alone — an unlabelled glyph is not self-evident and has no hover
/// on touch, so the icon never has to carry meaning by itself.
class _AccountBlock extends StatelessWidget {
  final ApiClient api;
  final SyncEngine sync;
  final DateTime? lastSynced;
  final VoidCallback onSignIn;
  final VoidCallback onOpenAccount;
  final Future<void> Function() onSyncNow;

  const _AccountBlock({
    required this.api,
    required this.sync,
    required this.lastSynced,
    required this.onSignIn,
    required this.onOpenAccount,
    required this.onSyncNow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<Session?>(
      stream: api.auth.sessions,
      initialData: api.auth.current,
      builder: (context, sessionSnapshot) {
        final signedIn = sessionSnapshot.data != null;

        return StreamBuilder<SyncState>(
          stream: sync.state,
          builder: (context, syncSnapshot) {
            final status = syncSnapshot.data?.status ?? SyncStatus.idle;
            final subtitle = _subtitle(status, signedIn);

            return ListTile(
              leading: Icon(
                signedIn ? AppIcons.accountSignedIn : AppIcons.accountSignedOut,
              ),
              title: Text(signedIn ? 'Signed in' : 'Not signed in'),
              subtitle: Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: IconButton(
                icon: Icon(_icon(status, signedIn)),
                tooltip: 'Sync now, $subtitle',
                onPressed: signedIn && status != SyncStatus.syncing
                    ? onSyncNow
                    : null,
              ),
              onTap: signedIn ? onOpenAccount : onSignIn,
            );
          },
        );
      },
    );
  }

  String _subtitle(SyncStatus status, bool signedIn) {
    if (!signedIn) return 'Sign in to carry your place';

    return switch (status) {
      SyncStatus.syncing => 'Syncing',
      SyncStatus.offline => 'Offline. Changes are queued.',
      SyncStatus.failed => 'Last sync failed',
      _ => describeLastSynced(lastSynced),
    };
  }

  IconData _icon(SyncStatus status, bool signedIn) {
    if (!signedIn) return AppIcons.syncSignedOut;

    return switch (status) {
      SyncStatus.syncing => AppIcons.syncRunning,
      SyncStatus.offline => AppIcons.syncOffline,
      SyncStatus.failed => AppIcons.syncFailed,
      _ => AppIcons.syncIdle,
    };
  }
}

/// One section, its current value, and the way into it.
class _IndexRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  const _IndexRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      // The value under the title rather than beside it. Beside it is what
      // the wireframe drew, and at the text sizes this app is built for the
      // two collide before either wraps.
      subtitle: Text(
        value,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(AppIcons.openSection),
      onTap: onTap,
    );
  }
}
