import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../theme/app_icons.dart';
import 'control_row.dart';
import 'profile_presentation.dart';

/// The overflow menu button of the row for the profile with [id].
Key profileRowMenuKey(String id) => ValueKey('profileRowMenu.$id');

/// The `Save as file` item in a row's overflow menu.
const profileExportItemKey = ValueKey('profileExportItem');

/// One profile in a list: selection state, a description, and an overflow
/// menu for what else can be done with it.
///
/// Shared between [ProfilesScreen] and the reader's own profile switcher, so
/// the one rule about what a preset's menu omits — no Delete — lives in one
/// place rather than two lists agreeing on it by accident.
class ProfileRow extends StatelessWidget {
  final ReadingProfile profile;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback? onDelete;

  /// Saves the profile as a file. Null leaves `Save as file` off the menu,
  /// the same optional-callback pattern as [onDelete]; the reader's switcher
  /// passes none.
  final VoidCallback? onExport;

  const ProfileRow({
    super.key,
    required this.profile,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onDuplicate,
    this.onDelete,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return ControlRow(
      selected: selected,
      icon: selected ? AppIcons.chosen : AppIcons.notChosen,
      title: profile.name,
      supportingText: describeProfile(profile),
      onTap: onSelect,
      trailing: PopupMenuButton<String>(
        key: profileRowMenuKey(profile.id),
        // Named rather than an icon row: a reader who needs 48pt type is not
        // well served by three small targets crammed into a list row.
        tooltip: 'Options for ${profile.name}',
        icon: const Icon(AppIcons.tileMenu),
        onSelected: (value) => switch (value) {
          'edit' => onEdit(),
          'duplicate' => onDuplicate(),
          'export' => onExport?.call(),
          'delete' => onDelete?.call(),
          _ => null,
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          const PopupMenuItem(value: 'duplicate', child: Text('Make a copy')),
          if (onExport != null)
            const PopupMenuItem(
              key: profileExportItemKey,
              value: 'export',
              child: Text('Save as file'),
            ),
          if (onDelete != null)
            PopupMenuItem(
              value: 'delete',
              child: Text(
                'Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
