import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import '../theme/appearance.dart';
import 'appearance_screen.dart';
import 'profile_edit_screen.dart';
import 'profile_presentation.dart';

/// Reading profiles: which one is in use, and editing the reader's own.
///
/// Separate from the reader screen on purpose. The reader has a switcher for
/// changing profile mid-book; this is where profiles are made and changed.
///
/// Built-in presets are not editable. Each is tied to a specific finding in
/// `docs/research/rsvp-evidence.md`, so a preset edited past recognition
/// would carry a name that no longer describes it, with no way back to the
/// tested starting point. Editing one produces a copy instead, which also
/// means a preset improved in a later release does not collide with a
/// reader's modified version of the old one.
class SettingsScreen extends StatefulWidget {
  final LibraryRepository repository;

  /// Supplies a clock stamp for each write. Pass `syncEngine.issueStamp`.
  ///
  /// Injected rather than taking the engine itself: this screen needs a
  /// stamp, not a sync engine, and a fake in a test should not have to be
  /// one.
  final Future<String> Function() issueStamp;

  /// Handed to [AppearanceScreen], which is reached from the row at the top
  /// of this list. Appearance is not a reading profile and does not belong
  /// on a screen called Reading profiles; it sits here because this is the
  /// only settings surface the app has until the navigation shell lands,
  /// and the row moves to a settings index then.
  final AppearanceController appearance;

  const SettingsScreen({
    super.key,
    required this.repository,
    required this.issueStamp,
    required this.appearance,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _loadActive();
  }

  Future<void> _loadActive() async {
    // Resolved rather than read raw, so a pointer at a profile deleted on
    // another device shows Standard selected instead of nothing.
    final active = await widget.repository.activeProfile();
    if (!mounted) return;
    setState(() => _activeId = active.id);
  }

  Future<void> _select(ReadingProfile profile) async {
    await widget.repository.setActiveProfile(
      profile.id,
      hlc: await widget.issueStamp(),
    );
    if (!mounted) return;
    setState(() => _activeId = profile.id);
  }

  Future<void> _duplicate(ReadingProfile source) async {
    final copy = source.fork(id: ReadingProfile.newId());
    await widget.repository.saveProfile(copy, hlc: await widget.issueStamp());
    if (!mounted) return;
    await _edit(copy);
  }

  Future<void> _edit(ReadingProfile profile) async {
    final result = await Navigator.of(context).push<ReadingProfile>(
      MaterialPageRoute(
        builder: (_) => ProfileEditScreen(
          profile: profile,
          repository: widget.repository,
          issueStamp: widget.issueStamp,
        ),
      ),
    );

    if (!mounted) return;

    // The editor forked a preset. A reader who customised the profile they
    // were reading with means to read with the result, so the selection
    // follows rather than staying on the untouched preset.
    if (result != null && result.id != profile.id && _activeId == profile.id) {
      await _select(result);
      return;
    }

    await _loadActive();
  }

  Future<void> _delete(ReadingProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${profile.name}?'),
        content: const Text(
          'This removes it from every device signed in to your account. '
          'Presets are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await widget.repository.deleteProfile(
      profile.id,
      hlc: await widget.issueStamp(),
    );

    // Deleting the active profile clears the pointer in the repository, so
    // this reads back as Standard rather than as a dangling id.
    await _loadActive();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reading profiles')),
      body: StreamBuilder<List<ReadingProfile>>(
        stream: widget.repository.watchProfiles(),
        builder: (context, snapshot) {
          final profiles = snapshot.data;
          if (profiles == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final presets = profiles.where((p) => p.isBuiltIn).toList();
          final mine = profiles.where((p) => !p.isBuiltIn).toList();

          return ListView(
            children: [
              const _SectionHeader('The app'),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Appearance'),
                subtitle: const Text(
                  'Light or dark, accent colour, and high contrast for the '
                  'app around your books.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        AppearanceScreen(controller: widget.appearance),
                  ),
                ),
              ),

              const _SectionHeader('Your profiles'),
              if (mine.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'None yet. Copy a preset below to make one you can '
                    'change.',
                  ),
                ),
              for (final profile in mine)
                _ProfileRow(
                  profile: profile,
                  selected: profile.id == _activeId,
                  onSelect: () => _select(profile),
                  onEdit: () => _edit(profile),
                  onDuplicate: () => _duplicate(profile),
                  onDelete: () => _delete(profile),
                ),

              const _SectionHeader('Presets'),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Starting points that ship with the app. Copy one to '
                  'change it.',
                ),
              ),
              for (final profile in presets)
                _ProfileRow(
                  profile: profile,
                  selected: profile.id == _activeId,
                  onSelect: () => _select(profile),
                  onEdit: () => _edit(profile),
                  onDuplicate: () => _duplicate(profile),
                ),

              const Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 32),
                child: Text(
                  'Your profiles follow you between devices. Which one is '
                  'selected does not: a phone read outdoors and a desktop in '
                  'a dim room can want different ones.',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _ProfileRow extends StatelessWidget {
  final ReadingProfile profile;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback? onDelete;

  const _ProfileRow({
    required this.profile,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onDuplicate,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      ),
      title: Text(profile.name),
      subtitle: Text(describeProfile(profile)),
      onTap: onSelect,
      trailing: PopupMenuButton<String>(
        // Named rather than an icon row: a reader who needs 48pt type is not
        // well served by three small targets crammed into a list row.
        tooltip: 'Options for ${profile.name}',
        onSelected: (value) => switch (value) {
          'edit' => onEdit(),
          'duplicate' => onDuplicate(),
          'delete' => onDelete?.call(),
          _ => null,
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'edit',
            child: Text(profile.isBuiltIn ? 'View settings' : 'Edit'),
          ),
          const PopupMenuItem(value: 'duplicate', child: Text('Make a copy')),
          if (onDelete != null)
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}
