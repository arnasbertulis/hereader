import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import 'profile_edit_screen.dart';

/// Duplicates and deletes a reading profile, including the confirmation
/// copy, so `ReaderScreen` and `ProfilesScreen` enact one policy instead of
/// each writing it out in full. Same shape as `BookOpener`: it holds no
/// state and no [BuildContext] because a reader can duplicate or delete from
/// either screen, and a second copy of either sequence would drift from the
/// first without anything failing. ADR 0011 names that shape: two paths
/// writing one fact is how they come apart.
///
/// Each call takes the context of the widget that started it, so the object
/// can sit in a [State] field for the life of a screen while the context it
/// uses stays scoped to one call.
class ProfileActions {
  final LibraryRepository repository;
  final Future<String> Function() issueStamp;

  const ProfileActions({required this.repository, required this.issueStamp});

  /// Forks [source], makes the fork active, and opens it for editing.
  ///
  /// The fork is selected before the editor opens: the reader asked to make
  /// it and is about to customise it, not carry on with whatever was active
  /// before it existed. If the editor forks again — editing a preset always
  /// does — the second fork replaces it as active in turn.
  Future<void> duplicate(BuildContext context, ReadingProfile source) async {
    final copy = source.fork(id: ReadingProfile.newId());
    await repository.saveProfile(copy, hlc: await issueStamp());
    if (!context.mounted) return;

    await repository.setActiveProfile(copy.id, hlc: await issueStamp());
    if (!context.mounted) return;

    final result = await Navigator.of(context).push<ReadingProfile>(
      MaterialPageRoute(
        builder: (_) => ProfileEditScreen(
          profile: copy,
          repository: repository,
          issueStamp: issueStamp,
        ),
      ),
    );
    if (!context.mounted) return;

    if (result != null && result.id != copy.id) {
      await repository.setActiveProfile(result.id, hlc: await issueStamp());
    }
  }

  /// Confirms, then deletes [profile]. Returns whether it was deleted.
  ///
  /// The confirmation wording lives here, not in each screen, so changing
  /// what deletion warns about is one edit rather than two that can drift
  /// apart.
  Future<bool> delete(BuildContext context, ReadingProfile profile) async {
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
    if (confirmed != true || !context.mounted) return false;

    await repository.deleteProfile(profile.id, hlc: await issueStamp());
    return true;
  }
}
