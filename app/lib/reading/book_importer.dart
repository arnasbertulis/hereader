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
/// for the open path: stateless, no held [BuildContext], a context taken
/// per call. Home, the Library and Free books each keep one instance rather
/// than re-spelling parse-then-write-then-report at three call sites in
/// three slightly different words.
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
  Future<ImportOutcome> importPickedFile(BuildContext context) async {
    final bytes = await pickBytes();
    if (bytes == null) return ImportOutcome.cancelled;
    if (!context.mounted) return ImportOutcome.cancelled;

    return importBytes(context, bytes);
  }

  /// Parses [bytes] and writes the result onto the shelf.
  ///
  /// Bytes rather than a picked file, so Free books can hand this the bytes
  /// of a Catalogue download without inventing a file that was never on
  /// disk.
  Future<ImportOutcome> importBytes(
    BuildContext context,
    Uint8List bytes,
  ) async {
    try {
      final book = await parser.import(bytes);
      await repository.addBook(book, bytes);
      return ImportOutcome.imported;
    } on EpubException catch (e) {
      if (context.mounted) _report(context, e.message);
      return ImportOutcome.failed;
    }
  }

  void _report(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
