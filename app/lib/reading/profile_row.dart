import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../theme/app_icons.dart';
import 'profile_presentation.dart';

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

  const ProfileRow({
    super.key,
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
      leading: Icon(selected ? AppIcons.chosen : AppIcons.notChosen),
      title: Text(profile.name),
      subtitle: Text(describeProfile(profile)),
      onTap: onSelect,
      trailing: PopupMenuButton<String>(
        // Named rather than an icon row: a reader who needs 48pt type is not
        // well served by three small targets crammed into a list row.
        tooltip: 'Options for ${profile.name}',
        icon: const Icon(AppIcons.tileMenu),
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
