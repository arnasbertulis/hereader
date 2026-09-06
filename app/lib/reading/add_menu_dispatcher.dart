import 'package:flutter/material.dart';

import '../catalogue/catalogue_client.dart';
import '../data/library_repository.dart';
import '../sync/sync_engine.dart';
import 'add_menu.dart';
import 'book_importer.dart';
import 'free_books_screen.dart';
import 'note_editor_screen.dart';
import 'paste_reader_screen.dart';

/// Acts on whatever the Add menu comes back with.
///
/// One dispatcher for both shelves that offer the menu, rather than each
/// carrying its own copy of the switch below — see [AddMenu]'s own comment
/// for what came of that the last time it drifted. [showAndAct] is the menu's
/// own opener; [act] is for a caller that already knows the answer, such as
/// the library's per-filter empty state, which asks for one option by name
/// rather than reopening the menu to get it.
///
/// Navigates rather than reporting an answer back: a dispatcher that only
/// decided would leave the duplicated navigation in place, which is the
/// entire complaint #302 opened against. Holds no build context of its own —
/// one is taken per call, matching [BookOpener] and [BookImporter] — and
/// holds one [BookImporter] of its own rather than asking a caller for one,
/// since the seam a test needs to stand in for the real file picker belongs
/// here now, not on every screen that used to build its own.
class AddMenuDispatcher {
  final LibraryRepository repository;
  final SyncEngine sync;
  final CatalogueClient catalogue;
  final BookImporter importer;

  AddMenuDispatcher({
    required this.repository,
    required this.sync,
    required this.catalogue,
    BookImporter? importer,
  }) : importer = importer ?? BookImporter(repository: repository);

  /// Opens the Add menu and acts on whatever it comes back with. A dismissed
  /// menu (null) does nothing.
  ///
  /// [onImportStarted] is forwarded to [act] — see its own comment for what
  /// it's for.
  Future<void> showAndAct(
    BuildContext context, {
    VoidCallback? onImportStarted,
  }) async {
    final choice = await showDialog<AddChoice>(
      context: context,
      builder: (_) => const AddMenu(),
    );

    if (choice == null || !context.mounted) return;
    await act(context, choice, onImportStarted: onImportStarted);
  }

  /// Acts on a given answer directly, without showing the menu.
  ///
  /// Only [AddChoice.epub] is slow — [BookImporter.importPickedFile] parses
  /// and writes before it returns. The other three push a route without
  /// waiting for it to be popped, matching the free-standing free books and
  /// paste navigation this replaced; the note branch's old copy did await
  /// its own push, but nothing read that wait — a note lands in the Library
  /// through [LibraryRepository.addBook] the moment it's saved, not through
  /// this route's result — so dropping it is a deliberate move to "navigate
  /// immediately" for all three, not a leftover.
  ///
  /// [onImportStarted], for the [AddChoice.epub] branch only, is
  /// [BookImporter.importPickedFile]'s `onPicked` — it fires once bytes
  /// exist and before the parse starts, never on a cancel. A caller raising
  /// its own busy flag from it, rather than from the top of this call, never
  /// sees that flag toggle for the time the file chooser itself is open
  /// (#269).
  Future<void> act(
    BuildContext context,
    AddChoice choice, {
    VoidCallback? onImportStarted,
  }) async {
    switch (choice) {
      case AddChoice.freeBooks:
        _openFreeBooks(context);
      case AddChoice.epub:
        await importer.importPickedFile(context, onPicked: onImportStarted);
      case AddChoice.paste:
        _openPaste(context);
      case AddChoice.note:
        _openNote(context);
    }
  }

  void _openFreeBooks(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FreeBooksScreen(
          client: catalogue,
          repository: repository,
          sync: sync,
          bookImporter: importer,
        ),
      ),
    );
  }

  void _openPaste(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PasteReaderScreen(
          repository: repository,
          issueStamp: sync.issueStamp,
        ),
      ),
    );
  }

  void _openNote(BuildContext context) {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(repository: repository, sync: sync),
      ),
    );
  }
}
