import 'dart:typed_data';

import 'package:epub_reader/epub_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import 'library_book.dart';

/// What became of one attempt to bring a book onto the shelf.
///
/// [cancelled] and [failed] are kept apart rather than folded into a
/// nullable [LibraryBook] because they are exactly the two cases a caller
/// needs to tell apart: a cancelled pick leaves everything — a filter, a
/// message — exactly as it was, and a failed one is worth restating.
enum ImportOutcome { imported, cancelled, failed }

/// Picks EPUB bytes off the reader's device, or returns null if they backed
/// out of the dialog. Overridable so a test can hand back bytes, or nothing,
/// without a real file dialog.
typedef PickEpubBytes = Future<Uint8List?> Function();

/// Carries a parse failure's message back to whatever the caller still has —
/// a [BuildContext] if it is still mounted, or nowhere.
typedef ReportImportFailure = void Function(String message);

/// The real picker. [FilePicker.pickFile] rather than [FilePicker.pickFiles]
/// plus an unwrap: the latter only reaches single-file behaviour through
/// `pickFiles`'s deprecated `allowMultiple` parameter.
Future<Uint8List?> _pickEpubFile() async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['epub'],
  );

  if (picked == null) return null;
  return picked.readAsBytes();
}

/// Carries an EPUB — picked off the reader's device, or already downloaded —
/// onto the shelf.
///
/// Parses, writes, and reports its own failures, the way [BookOpener] does
/// for the open path: stateless, no held [BuildContext]. [importBytes] and
/// [importPickedFile] take a context per call, the way [BookOpener] does;
/// [writeBytes] takes none, for a caller — Free books — whose write can
/// outlive the [BuildContext] it started with. Home, the Library and Free
/// books each keep one instance rather than re-spelling
/// parse-then-write-then-report at three call sites in three slightly
/// different words.
///
/// Deciding whether to open a book already in the Library instead of
/// importing it again is not this module's job. Only Free books ever faces
/// that choice — a file picked off disk or pasted in cannot already be on
/// the shelf under a different origin — so that decision, and the navigation
/// it leads to, stays on the screen that needs it.
class BookImporter {
  final LibraryRepository repository;
  final BookParser parser;
  final PickEpubBytes pickBytes;

  const BookImporter({
    required this.repository,
    this.parser = const BookParser(),
    this.pickBytes = _pickEpubFile,
  });

  /// Asks the reader to pick a file, then imports it.
  ///
  /// A null pick — the reader backed out of the dialog — reports
  /// [ImportOutcome.cancelled] rather than running [importBytes] at all, so
  /// a cancel never touches the repository or [context].
  ///
  /// [onPicked], if given, runs once bytes exist and before the parse
  /// starts — never on a cancel. It is the only point between "the dialog is
  /// open" and "the write has landed", so it is where a caller raises its own
  /// busy affordance: before this, the reader is still looking at the file
  /// chooser, not this screen, and a busy state painted any earlier would
  /// paint and unpaint around a cancel that never touched anything.
  Future<ImportOutcome> importPickedFile(
    BuildContext context, {
    VoidCallback? onPicked,
  }) async {
    final bytes = await pickBytes();
    if (bytes == null) return ImportOutcome.cancelled;
    if (!context.mounted) return ImportOutcome.cancelled;

    onPicked?.call();
    return importBytes(context, bytes);
  }

  /// Parses [bytes] and writes the result onto the shelf, reporting a parse
  /// failure through [context].
  ///
  /// Bytes rather than a picked file, so Free books can hand this the bytes
  /// of a Catalogue download without inventing a file that was never on
  /// disk. Kept for a caller that is certain its [context] is still mounted
  /// — see [writeBytes] for one that is not.
  Future<ImportOutcome> importBytes(
    BuildContext context,
    Uint8List bytes,
  ) {
    return writeBytes(
      bytes,
      onFailed: (message) {
        if (context.mounted) _report(context, message);
      },
    );
  }

  /// Parses [bytes] and writes the result onto the shelf, without a
  /// [BuildContext].
  ///
  /// Free books calls this once a download might outlive the screen that
  /// started it: reading `State.context` after `dispose` throws, so a
  /// `mounted` check taken before the write cannot guard a context-taking
  /// call the way it guards a `setState` — it can only skip the write
  /// entirely, which is the bug this method exists to avoid. [onFailed], if
  /// given, is called with a parse failure's message; the caller decides
  /// whether it still has anywhere to show it.
  Future<ImportOutcome> writeBytes(
    Uint8List bytes, {
    ReportImportFailure? onFailed,
  }) async {
    try {
      final book = await parser.import(bytes);
      await repository.addBook(book, bytes);
      return ImportOutcome.imported;
    } on EpubException catch (e) {
      onFailed?.call(e.message);
      return ImportOutcome.failed;
    }
  }

  void _report(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
