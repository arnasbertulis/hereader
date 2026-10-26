import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import 'mode_fork.dart';
import 'profile_edit_screen.dart';
import 'profile_file.dart';

/// Picks a profile file off the reader's device, or returns null if they
/// backed out of the dialog. The real one returns at most
/// [profileFileMaxBytes] + 1 bytes; a file that long is refused as too large.
/// Overridable so a test can hand back bytes, or nothing, without a real file
/// dialog.
typedef PickProfileBytes = Future<Uint8List?> Function();

/// Hands a profile file to the platform to save: a browser download on web, a
/// document on Android, a save dialog on Windows. Overridable so a test can
/// see what would have been written without a real file dialog.
typedef SaveProfileBytes =
    Future<void> Function(String fileName, Uint8List bytes);

/// The real picker. Reads at most [profileFileMaxBytes] + 1 bytes of the file
/// ([readProfileFileBytes]), so a huge file is never buffered whole.
Future<Uint8List?> pickProfileFile() async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );

  if (picked == null) return null;
  return readProfileFileBytes(picked.readAsByteStream());
}

/// The real saver. A null result from the plugin is either a cancel or the
/// browser having handled the download itself, and the two cannot be told
/// apart, so it is never announced as a failure.
Future<void> saveProfileFile(String fileName, Uint8List bytes) async {
  await FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: 'application/json',
  );
}

/// The snackbar announcing an imported profile. Keyed so a test finds it
/// without matching its wording.
const profileImportedKey = ValueKey('profileImported');

/// The text explaining why [reason] was refused, keyed per reason.
Key profileRejectionKey(ProfileFileRejection reason) =>
    ValueKey('profileRejection.${reason.name}');

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

  final PickProfileBytes pickBytes;
  final SaveProfileBytes saveBytes;

  const ProfileActions({
    required this.repository,
    required this.issueStamp,
    this.pickBytes = pickProfileFile,
    this.saveBytes = saveProfileFile,
  });

  /// Saves [profile] as a profile file. Cancelling the dialog is not an
  /// error and says nothing.
  Future<void> exportToFile(ReadingProfile profile) =>
      saveBytes(profileFileName(profile), encodeProfileFile(profile));

  /// Asks the reader for a profile file and stores it as a new profile.
  ///
  /// Always a new stored profile with a fresh id, never an overwrite. The
  /// import becomes the active profile and is announced the way [duplicate]
  /// announces a fork, with an Undo that restores whichever profile was
  /// active before; the imported profile stays stored. A cancelled pick does
  /// nothing. A refused file stores nothing and says why.
  Future<void> importFromFile(BuildContext context) async {
    final bytes = await pickBytes();
    if (bytes == null || !context.mounted) return;

    final result = decodeProfileFile(bytes, id: ReadingProfile.newId());
    switch (result) {
      case ProfileFileRejected(:final reason):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _rejectionCopy(reason),
              key: profileRejectionKey(reason),
            ),
          ),
        );
      case ProfileFileDecoded(:final profile):
        await _storeImported(context, profile);
    }
  }

  Future<void> _storeImported(
    BuildContext context,
    ReadingProfile decoded,
  ) async {
    final outgoingId = (await repository.activeProfile()).id;
    final taken = {
      for (final p in await repository.allProfiles()) p.name,
      // The sliding switch removes a fork still carrying its generated name,
      // so an import must never arrive under one.
      for (final preset in Presets.all)
        for (final mode in PresentationMode.values)
          generatedForkName(preset, mode),
    };
    final profile = taken.contains(decoded.name)
        ? decoded.copyWith(name: '${decoded.name} (imported)')
        : decoded;

    await repository.saveProfile(profile, hlc: await issueStamp());
    if (!context.mounted) return;

    await repository.setActiveProfile(profile.id, hlc: await issueStamp());
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Now reading with ${profile.name}',
          key: profileImportedKey,
        ),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(_restoreActive(outgoingId)),
        ),
      ),
    );
  }

  String _rejectionCopy(ProfileFileRejection reason) => switch (reason) {
    ProfileFileRejection.tooLarge =>
      'That file is too large to be a reading profile.',
    ProfileFileRejection.notAProfile =>
      'That file is not a hereader reading profile.',
    ProfileFileRejection.newerVersion =>
      'That profile was saved by a newer version of hereader. Update the '
          'app to open it.',
  };

  /// Forks [source], makes the fork active, and opens it for editing.
  ///
  /// The fork is selected before the editor opens: the reader asked to make
  /// it and is about to customise it, not carry on with whatever was active
  /// before it existed. If the editor forks again — editing a preset always
  /// does — the second fork replaces it as active in turn.
  ///
  /// The switch is announced after the editor closes, with an undo that
  /// restores whichever profile was active before this call started, even if
  /// the editor forked again while it was open. The [SnackBar] outlives the
  /// 4-second default: this app's audience is exactly the audience likely to
  /// miss a short-lived announcement.
  Future<void> duplicate(BuildContext context, ReadingProfile source) async {
    final outgoingId = (await repository.activeProfile()).id;

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

    final active = result ?? copy;
    if (result != null && result.id != copy.id) {
      await repository.setActiveProfile(result.id, hlc: await issueStamp());
    }
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Now reading with ${active.name}'),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(_restoreActive(outgoingId)),
        ),
      ),
    );
  }

  /// Restores [id] as active, for the duplicate-announcement's undo.
  ///
  /// A private helper rather than an inline closure so the undo captures
  /// [id] as it was when [duplicate] started, never whatever the editor left
  /// active by the time the reader taps it.
  Future<void> _restoreActive(String id) async {
    await repository.setActiveProfile(id, hlc: await issueStamp());
  }

  /// Confirms, then deletes [profile]. Returns whether it was deleted.
  ///
  /// The confirmation wording lives here, not in each screen, so changing
  /// what deletion warns about is one edit rather than two that can drift
  /// apart. [signedIn] decides which consequence it states: a signed-in
  /// reader's profiles sync, so deleting one reaches every device; a
  /// signed-out reader's profiles never leave this device.
  Future<bool> delete(
    BuildContext context,
    ReadingProfile profile, {
    required bool signedIn,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${profile.name}?'),
        content: Text(
          signedIn
              ? 'This removes it from every device signed in to your '
                    'account. Presets are not affected.'
              : 'This removes it from this device. Presets are not '
                    'affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
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
