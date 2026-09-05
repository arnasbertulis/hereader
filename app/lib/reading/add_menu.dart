import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_tokens.dart';

/// What the add menu came back with.
///
/// Shared between the library and Home rather than declared once per screen:
/// both open the same dialog and act on the same four answers, and a second
/// enum meaning the same thing would only invite the two to drift.
enum AddChoice { freeBooks, epub, paste, note }

/// Same argument as `readerPlayButtonKey` and `libraryAddButtonKey`: a test
/// that wants "the Free books option" should not have to spell out the copy
/// printed on it to get there.
const Key addMenuFreeBooksKey = Key('add-menu-free-books');

/// See [addMenuFreeBooksKey].
const Key addMenuEpubKey = Key('add-menu-epub');

/// See [addMenuFreeBooksKey].
const Key addMenuNoteKey = Key('add-menu-note');

/// See [addMenuFreeBooksKey].
const Key addMenuPasteKey = Key('add-menu-paste');

/// Four ways to start reading, stacked.
///
/// The library's own add button opens this, and so does Home's empty state —
/// one dialog, asked from two places, rather than Home keeping a shorter,
/// two-option version of its own. Home used to: two buttons, EPUB and paste,
/// with no way to write a note at all. That was not a deliberate scope cut,
/// it was the two screens drifting out of sync the way [_AddMenuOption]'s own
/// note below once had to correct for.
///
/// Full-width blocks rather than a list of compact rows, and each one is the
/// tap target: a reader who cannot reliably hit a small target gets a box the
/// size of a hand instead of a 48dp row.
///
/// Each block says what it does and what happens to it afterwards. Free
/// books, EPUB and note all stay in the library; paste does not, and a
/// reader finding that out later is a reader who lost something.
class AddMenu extends StatelessWidget {
  const AddMenu({super.key});

  /// Wide enough to hold two lines of explanation on a phone, capped before
  /// it becomes a dialog the width of a monitor holding two words.
  static const double _maxWidth = 480;

  /// Tall enough that each block is a target rather than a row. Grows with
  /// the reader's text size; the whole panel scrolls once it has to.
  static const double _minOptionHeight = 148;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Add something to read',
      child: Dialog(
        // Clipped so an ink ripple in either half stops at the rounded
        // corner rather than painting over it.
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: theme.dividerTheme.thickness ?? AppHairline.width,
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _maxWidth,
            maxHeight: size.height * 0.8,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AddMenuOption(
                  key: addMenuFreeBooksKey,
                  choice: AddChoice.freeBooks,
                  icon: AppIcons.tabLibrary,
                  title: 'Free books',
                  detail:
                      'Free books from a public catalogue. Pick one to '
                      'download it to this device; it stays in your library '
                      'like any other book.',
                  minHeight: _minOptionHeight,
                ),
                const Divider(),
                _AddMenuOption(
                  key: addMenuEpubKey,
                  choice: AddChoice.epub,
                  icon: AppIcons.importFile,
                  title: 'Add an EPUB',
                  detail:
                      'A book file from this device. It stays in your '
                      'library and remembers your place.',
                  minHeight: _minOptionHeight,
                ),
                // Takes its colour and weight from the app's one divider
                // theme, so it thickens with the rest of them under high
                // contrast.
                const Divider(),
                _AddMenuOption(
                  key: addMenuNoteKey,
                  choice: AddChoice.note,
                  icon: AppIcons.writeNote,
                  title: 'Write a note',
                  detail:
                      'Type something to read. It stays in your '
                      'library like any other book.',
                  minHeight: _minOptionHeight,
                ),
                const Divider(),
                _AddMenuOption(
                  key: addMenuPasteKey,
                  choice: AddChoice.paste,
                  icon: AppIcons.pasteText,
                  title: 'Paste text',
                  detail:
                      'Read anything you have copied. Nothing is saved, '
                      'and it is gone when you close it.',
                  minHeight: _minOptionHeight,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddMenuOption extends StatelessWidget {
  final AddChoice choice;
  final IconData icon;
  final String title;
  final String detail;
  final double minHeight;

  const _AddMenuOption({
    super.key,
    required this.choice,
    required this.icon,
    required this.title,
    required this.detail,
    required this.minHeight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      label: '$title. $detail',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(choice),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: scheme.onSurface),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
