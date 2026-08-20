/// Pairing a stored profile back to the preset the sliding switch forked it
/// from.
///
/// The switch in the reader's profile sheet cannot edit a preset — built-ins
/// live in code and are not stored — so turning sliding on forks the preset
/// and selects the fork. Turning it off again used to leave that fork
/// selected with its mode flipped, which left a profile called
/// "Standard (sliding)" showing one word at a time. The switch has to be
/// reversible, and reversing it means finding the way back.
///
/// There is no lineage field to follow. Recording one would cost a column, a
/// migration and a wire change to hold a fact that is already derivable: a
/// fork the reader has not otherwise touched *is* the preset, in every field
/// that matters. So the pairing is computed by value and fails closed —
/// anything that does not match exactly is the reader's own profile and is
/// left alone.
///
/// Compared through `toJson` because these are plain data classes with no
/// value equality of their own. Both sides go through the same encoder, so
/// two encodings match exactly when the values do.
library;

import 'dart:convert';

import 'package:rsvp_engine/rsvp_engine.dart';

/// A preset a stored profile could have come from, and how far it has since
/// moved from it.
///
/// [caretOnly] means the fork differs from its preset in the caret settings
/// as well as the mode. Those settings only exist under sliding and only
/// appear in the editor there, so adjusting them is the expected thing to do
/// inside a fork and must not cost the reader the fork itself.
typedef ModeFork = ({ReadingProfile preset, bool caretOnly});

/// The preset [profile] is a sliding fork of, or null if it is its own thing.
///
/// Null for a preset, for a profile matching none of them, and for one the
/// reader has changed in any way beyond the mode and the caret.
ModeFork? presetBehind(ReadingProfile profile) {
  if (profile.isBuiltIn) return null;

  final exact = _fingerprint(profile, ignoreCaret: false);
  final loose = _fingerprint(profile, ignoreCaret: true);

  for (final preset in Presets.all) {
    if (exact == _fingerprint(preset, ignoreCaret: false)) {
      return (preset: preset, caretOnly: false);
    }
    if (loose == _fingerprint(preset, ignoreCaret: true)) {
      return (preset: preset, caretOnly: true);
    }
  }
  return null;
}

/// A sliding fork of [preset] already in [profiles], or null.
///
/// Turning the switch on looks here before forking, so switching off and on
/// again returns the reader to the fork they had — with whatever caret
/// settings they chose in it — instead of leaving a second copy behind every
/// time. Deleted rows never reach [profiles], so a fork the reader removed
/// is not resurrected by this.
ReadingProfile? slidingForkOf(
  ReadingProfile preset,
  List<ReadingProfile> profiles,
) {
  for (final profile in profiles) {
    if (profile.presentation.mode != PresentationMode.continuousScroll) {
      continue;
    }
    if (presetBehind(profile)?.preset.id == preset.id) return profile;
  }
  return null;
}

/// A profile encoded with the fields a fork is allowed to differ in removed.
///
/// The id and the name are the fork's own by definition. The mode is what
/// the switch sets. The caret settings are dropped only for the looser of the
/// two comparisons, and they are matched by prefix so that a caret setting
/// added later is covered without this function being remembered.
String _fingerprint(ReadingProfile profile, {required bool ignoreCaret}) {
  final json = profile.toJson()
    ..remove('id')
    ..remove('name');

  final presentation = Map<String, dynamic>.from(
    json['presentation'] as Map<String, dynamic>,
  )..remove('mode');

  if (ignoreCaret) {
    presentation.removeWhere((key, _) => key.startsWith('caret'));
  }

  json['presentation'] = presentation;
  return jsonEncode(json);
}
