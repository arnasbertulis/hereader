import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import '../sync/api_client.dart';
import '../sync/auth_store.dart';
import '../sync/last_synced.dart';
import '../sync/sync_engine.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/appearance.dart';
import 'about_screen.dart';
import 'account_screen.dart';
import 'appearance_screen.dart';
import 'profiles_screen.dart';
import 'reading_display.dart';
import 'reading_settings_screen.dart';
import 'sync_screen.dart';

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

  /// For the Account row, which reads the session, and Sync, which runs one.
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
  String? _activeProfileName;
  DateTime? _lastSynced;

  @override
  void initState() {
    super.initState();
    _loadValues();
  }

  /// Reads the two values that are not already on a stream.
  ///
  /// Called again whenever a subpage returns, because a reader who just
  /// changed the active profile should not come back to a row still naming
  /// the old one.
  Future<void> _loadValues() async {
    // Resolved rather than read raw, so a pointer at a profile deleted on
    // another device names Standard instead of nothing.
    final active = await widget.repository.activeProfile();
    final synced = await widget.repository.preference(
      SyncEngine.lastSyncedAtKey,
    );

    if (!mounted) return;

    setState(() {
      _activeProfileName = active.name;
      _lastSynced = DateTime.tryParse(synced ?? '');
    });
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => screen));

    await _loadValues();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: widget.appearance,
        builder: (context, _) {
          return StreamBuilder<List<ReadingProfile>>(
            stream: widget.repository.watchProfiles(),
            builder: (context, snapshot) {
              final profiles = snapshot.data ?? const <ReadingProfile>[];

              return ListView(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                children: [
                  StreamBuilder<Session?>(
                    stream: widget.api.auth.sessions,
                    initialData: widget.api.auth.current,
                    builder: (context, session) => _IndexRow(
                      icon: Icons.person_outline,
                      title: 'Account',
                      value: session.data == null
                          ? 'Not signed in'
                          : 'Signed in',
                      onTap: () => _push(
                        AccountScreen(api: widget.api, sync: widget.sync),
                      ),
                    ),
                  ),
                  _IndexRow(
                    icon: Icons.text_fields_outlined,
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
                    icon: Icons.palette_outlined,
                    title: 'Appearance',
                    value: describeAppearance(widget.appearance.settings),
                    onTap: () =>
                        _push(AppearanceScreen(controller: widget.appearance)),
                  ),
                  _IndexRow(
                    icon: Icons.auto_stories_outlined,
                    title: 'Reading',
                    value: describeReading(widget.display.timeLeftScope),
                    onTap: () =>
                        _push(ReadingSettingsScreen(display: widget.display)),
                  ),
                  _IndexRow(
                    icon: Icons.sync_outlined,
                    title: 'Sync',
                    value: widget.api.auth.isSignedIn
                        ? describeLastSynced(_lastSynced)
                        : 'Off. Sign in to turn it on.',
                    onTap: () => _push(
                      SyncScreen(
                        repository: widget.repository,
                        api: widget.api,
                        sync: widget.sync,
                      ),
                    ),
                  ),
                  _IndexRow(
                    icon: Icons.info_outline,
                    title: 'About',
                    value:
                        'Licence, research, and what this app does not claim',
                    onTap: () => _push(const AboutScreen()),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// The active profile, and how many the reader has of their own.
  ///
  /// Presets are excluded from the count. Five of the profiles in that
  /// stream ship with the app, so counting them all would tell every reader
  /// they have five before they have made one.
  String _profilesValue(List<ReadingProfile> profiles) {
    final name = _activeProfileName;
    final mine = profiles.where((p) => !p.isBuiltIn).length;

    if (name == null) return 'Loading';
    if (mine == 0) return '$name · presets only';

    return '$name · $mine of your own';
  }
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
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
