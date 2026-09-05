/// Pairing a stored profile back to the preset the sliding switch forked it
/// from, and the policy the sliding switch enacts.
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
/// Compared through `toJson` with the id, the name and the mode masked out,
/// and the caret fields masked too for the looser of the two comparisons.
/// `ReadingProfile.==` cannot do this: it compares every field a profile
/// carries, and the id and the name are a fork's own by definition, so a
/// whole-value compare would call a fork unequal to its preset on the two
/// fields that are supposed to differ. Masking specific fields needs the map
/// `toJson` already produces.
///
/// No Flutter, no repository, no clock: the reading screen switches over the
/// outcome [decideMode] returns and performs the writes; this module only
/// decides what they should be.
library;

import 'dart:convert';

import 'package:rsvp_engine/rsvp_engine.dart';

/// A preset a stored profile could have come from, and whether the fork is
/// safe to remove once the reader leaves it.
///
/// [discardable] is false when the fork differs from its preset in the caret
/// settings as well as the mode. Those settings only exist under sliding and
/// only appear in the editor there, so adjusting them is the expected thing
/// to do inside a fork and must not cost the reader the fork itself.
typedef ModeFork = ({ReadingProfile preset, bool discardable});

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
      return (preset: preset, discardable: true);
    }
    if (loose == _fingerprint(preset, ignoreCaret: true)) {
      return (preset: preset, discardable: false);
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

/// What flipping the sliding switch does, described rather than performed.
///
/// [decideMode] returns one of these; the reading screen switches over it and
/// issues a stamp per write. Keeping the decision here rather than in the
/// screen is what makes it assertable without a widget pump or a database:
/// every branch below is a plain value comparison over its arguments.
sealed class ModeDecision {
  const ModeDecision();
}

/// Select [preset], discarding the fork the reader is leaving when [discard]
/// is not null.
///
/// [discard] is the profile the reader was just on. It is null when that
/// fork carries caret settings of the reader's own — [ModeFork.discardable]
/// false — so it is left in place, unselected, for [slidingForkOf] to find
/// again if sliding comes back on.
class ReturnToPreset extends ModeDecision {
  final ReadingProfile preset;
  final ReadingProfile? discard;
  const ReturnToPreset(this.preset, {this.discard});
}

/// Select [fork], a sliding fork of the active preset the reader already has.
///
/// Reached only when turning sliding on finds one via [slidingForkOf], so no
/// second fork is made for the same preset.
class SelectExistingFork extends ModeDecision {
  final ReadingProfile fork;
  const SelectExistingFork(this.fork);
}

/// Save [profile] in place. Its id does not change, so nothing needs
/// reselecting once the write lands.
///
/// Reached when the active profile is already the reader's own — not a
/// preset, and not a fork the switch would rather return to — so the mode
/// change is a plain edit like any other.
class SaveInPlace extends ModeDecision {
  final ReadingProfile profile;
  const SaveInPlace(this.profile);
}

/// Save [profile], a new fork of a preset, and select it once saved.
///
/// Presets cannot be saved, so turning sliding on forks the preset — the
/// rule this repo already has for "the reader changed a preset". Named after
/// the change rather than "(copy)": a reader who flipped one switch did not
/// ask for a duplicate.
class ForkAndSelect extends ModeDecision {
  final ReadingProfile profile;
  const ForkAndSelect(this.profile);
}

/// What putting [profile] into [mode] should do, given the reader's other
/// [profiles].
///
/// [profiles] is a parameter rather than a query this function runs itself,
/// so the decision stays synchronous: nothing here awaits, and a caller that
/// binds the active profile and calls this immediately has no gap where a
/// change arriving from another device could move the profile out from under
/// it. See `ReaderScreen._setMode`, which binds `_profile` once and passes it
/// straight through.
ModeDecision decideMode({
  required ReadingProfile profile,
  required PresentationMode mode,
  required List<ReadingProfile> profiles,
}) {
  final origin = presetBehind(profile);

  // Off, on a fork that has not been made the reader's own: go back to the
  // preset it came from.
  if (mode != PresentationMode.continuousScroll && origin != null) {
    return ReturnToPreset(
      origin.preset,
      discard: origin.discardable ? profile : null,
    );
  }

  // On, from a preset: reuse the fork this reader already has for it rather
  // than leaving a second one behind every time the switch goes round.
  if (mode == PresentationMode.continuousScroll && profile.isBuiltIn) {
    final existing = slidingForkOf(profile, profiles);
    if (existing != null) return SelectExistingFork(existing);
  }

  final changed = profile.copyWith(
    presentation: profile.presentation.copyWith(mode: mode),
  );

  if (!profile.isBuiltIn) return SaveInPlace(changed);

  return ForkAndSelect(
    changed.fork(
      id: ReadingProfile.newId(),
      name: '${profile.name} ${_modeSuffix(mode)}',
    ),
  );
}

/// The suffix a fork made by the sliding switch is named with.
///
/// Named per mode rather than defaulted, so a fourth [PresentationMode] is a
/// compile error here rather than a fork silently named after the wrong one.
String _modeSuffix(PresentationMode mode) => switch (mode) {
  PresentationMode.continuousScroll => '(sliding)',
  // Neither of these forks in practice — a preset only leaves `fixedSingle`
  // by way of the switch, and comes back by way of `ReturnToPreset`.
  PresentationMode.fixedSingle ||
  PresentationMode.shiftingWindow => '(one word)',
};
