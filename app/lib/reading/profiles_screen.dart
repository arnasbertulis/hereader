import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import '../sync/auth_store.dart';
import '../theme/content_width.dart';
import 'info_dot.dart';
import 'profile_actions.dart';
import 'profile_edit_screen.dart';
import 'profile_row.dart';
import 'section_header.dart';

/// Reading profiles: which one is in use, and editing the reader's own.
///
/// Separate from the reader screen on purpose. The reader has a switcher for
/// changing profile mid-book; this is where profiles are made and changed.
///
/// This was the whole of settings while settings was one screen. It is a
/// subpage now, reached from the index, and it carries the same body: the
/// live preview, the WCAG readout and the fade warning behave exactly as
/// they did.
///
/// Built-in presets are not editable. Each is tied to a specific finding in
/// `docs/research/rsvp-evidence.md`, so a preset edited past recognition
/// would carry a name that no longer describes it, with no way back to the
/// tested starting point. Editing one produces a copy instead, which also
/// means a preset improved in a later release does not collide with a
/// reader's modified version of the old one.
class ProfilesScreen extends StatefulWidget {
  final LibraryRepository repository;

  /// Supplies a clock stamp for each write. Pass `syncEngine.issueStamp`.
  ///
  /// Injected rather than taking the engine itself: this screen needs a
  /// stamp, not a sync engine, and a fake in a test should not have to be
  /// one.
  final Future<String> Function() issueStamp;

  /// Whether deleting a profile from here reaches every device or only this
  /// one. Pass `syncEngine.auth`. Optional and `null` in the widget tests
  /// that never exercise delete's confirmation copy; every real caller
  /// passes it.
  final AuthStore? auth;

  const ProfilesScreen({
    super.key,
    required this.repository,
    required this.issueStamp,
    this.auth,
  });

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  late final ProfileActions _profileActions;

  @override
  void initState() {
    super.initState();
    _profileActions = ProfileActions(
      repository: widget.repository,
      issueStamp: widget.issueStamp,
    );
  }

  Future<void> _select(ReadingProfile profile) async {
    // A plain write. The row moves when `watchActiveProfile` re-emits, the
    // same way it moves for a change written from another device — there is
    // no local copy of the pointer left to also update.
    await widget.repository.setActiveProfile(
      profile.id,
      hlc: await widget.issueStamp(),
    );
  }

  Future<void> _duplicate(ReadingProfile source) async {
    // ProfileActions.duplicate writes the fork's own pointer and announces
    // the switch; no reload needed here.
    await _profileActions.duplicate(context, source);
  }

  Future<void> _edit(ReadingProfile profile) async {
    // ProfileEditScreen forks a preset on its first change itself, activating
    // the fork and announcing the switch with its own Undo — the same
    // mechanism ProfileActions.duplicate uses for "Make a copy" above.
    await Navigator.of(context).push<ReadingProfile>(
      MaterialPageRoute(
        builder: (_) => ProfileEditScreen(
          profile: profile,
          repository: widget.repository,
          issueStamp: widget.issueStamp,
          auth: widget.auth,
        ),
      ),
    );
  }

  Future<void> _delete(ReadingProfile profile) async {
    // Deleting the active profile clears the pointer in the repository, and
    // `watchActiveProfile` resolves that back to Standard; no reload needed.
    await _profileActions.delete(
      context,
      profile,
      signedIn: widget.auth?.isSignedIn ?? false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reading profiles')),
      body: StreamBuilder<ReadingProfile>(
        // The same subscription Home and Library hold: a pointer in
        // `preferences` naming a row in `stored_profiles`, so a change
        // written anywhere — including another device — reaches the
        // selected row without this screen reloading anything by hand.
        stream: widget.repository.watchActiveProfile(),
        builder: (context, activeSnapshot) {
          // Null until the first emission, so no row reads as selected
          // before the pointer is actually known — never the wrong one.
          final activeId = activeSnapshot.data?.id;

          return StreamBuilder<List<ReadingProfile>>(
            stream: widget.repository.watchProfiles(),
            builder: (context, snapshot) {
              final profiles = snapshot.data;
              if (profiles == null) {
                return const Center(child: CircularProgressIndicator());
              }

              final presets = profiles.where((p) => p.isBuiltIn).toList();
              final mine = profiles.where((p) => !p.isBuiltIn).toList();

              return ContentWidth(
                child: ListView(
                  children: [
                    SectionHeader(
                      'Your profiles',
                      info: const InfoDot(
                        semanticLabel: 'About your profiles',
                        explanation:
                            'Your profiles follow you between devices. '
                            'Which one is selected does not: a phone read '
                            'outdoors and a desktop in a dim room can want '
                            'different ones.',
                      ),
                      supportingText: mine.isEmpty
                          ? 'Copy a preset below to make one you can change.'
                          : null,
                    ),
                    for (final profile in mine)
                      ProfileRow(
                        profile: profile,
                        selected: profile.id == activeId,
                        onSelect: () => _select(profile),
                        onEdit: () => _edit(profile),
                        onDuplicate: () => _duplicate(profile),
                        onDelete: () => _delete(profile),
                      ),

                    const SectionHeader(
                      'Presets',
                      supportingText: 'Copy one to make it your own.',
                    ),
                    for (final profile in presets)
                      ProfileRow(
                        profile: profile,
                        selected: profile.id == activeId,
                        onSelect: () => _select(profile),
                        onEdit: () => _edit(profile),
                        onDuplicate: () => _duplicate(profile),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
