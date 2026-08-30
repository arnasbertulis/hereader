import 'dart:convert';
import 'dart:typed_data';

import 'package:epub_reader/epub_reader.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../sync/sync_engine.dart';
import 'book_opener.dart';
import 'library_book.dart';

/// Writes a note and reads it back immediately, or edits one already in the
/// library.
///
/// Unlike [PasteReaderScreen], the text is stored: it gets a real id, a real
/// position that saves and syncs, and it is still in the library the next
/// time the reader opens it. See ADR 0017.
class NoteEditorScreen extends StatefulWidget {
  final LibraryRepository repository;
  final SyncEngine sync;

  /// The note being edited, or null when this is writing a new one. The id
  /// is stable across an edit — only the title and text change — so it is
  /// the one piece of the original that has nowhere else to come from.
  final String? noteId;

  /// Starting field contents. Empty for a new note; the stored title and
  /// text for an edit, read by the caller before this screen is pushed.
  final String initialTitle;
  final String initialBody;

  const NoteEditorScreen({
    super.key,
    required this.repository,
    required this.sync,
    this.noteId,
    this.initialTitle = '',
    this.initialBody = '',
  });

  bool get isEditing => noteId != null;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final _titleController = TextEditingController(
    text: widget.initialTitle,
  );
  late final _bodyController = TextEditingController(text: widget.initialBody);

  /// What was on disk when this screen opened, so a save can tell whether the
  /// text actually changed rather than merely being resubmitted.
  late final Uint8List _originalBytes = Uint8List.fromList(
    utf8.encode(widget.initialBody),
  );

  bool _busy = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _bodyController.text;
    if (body.trim().isEmpty) return;

    final title = _titleController.text.trim();
    final effectiveTitle = title.isEmpty ? 'Untitled note' : title;
    final bytes = Uint8List.fromList(utf8.encode(body));

    final id = widget.noteId ?? LibraryBook.newNoteId();
    final textChanged = !widget.isEditing || !listEquals(bytes, _originalBytes);

    if (widget.isEditing && textChanged) {
      final hadProgress = await widget.repository.positionOf(id) != null;

      if (hadProgress) {
        final confirmed = await _confirmReset();
        if (confirmed != true || !mounted) return;
      }
    }

    setState(() => _busy = true);

    try {
      final parsed = await const BookImporter().openNote(
        bytes,
        id: id,
        title: effectiveTitle,
      );

      if (widget.isEditing) {
        await widget.repository.editNote(
          parsed,
          bytes,
          resetProgress: textChanged,
        );
      } else {
        await widget.repository.addBook(parsed, bytes);
      }

      if (!mounted) return;

      // Opened through the same path every other book takes, rather than
      // pushed straight to ReaderScreen: this is what checks for a sync
      // conflict, re-reads the position sync may just have written, and
      // wires up the save callback ADR 0011 depends on. A freshly written
      // note has nothing to conflict with, and an edit that reset progress
      // opens at the start the same way a first read would; there is no
      // shorter route that does not duplicate BookOpener either way.
      final opener = BookOpener(
        repository: widget.repository,
        sync: widget.sync,
      );
      await opener.open(context, id);

      // Popped with a result rather than bare: the library's own add flow
      // tells a cancelled edit (nothing was ever written, this line never
      // runs) apart from a genuine save, and only the second should ever
      // change what the reader is looking at.
      if (mounted) Navigator.of(context).pop(true);
    } on EpubException catch (e) {
      _report(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks before an edit throws away a place the reader already has.
  ///
  /// Only reached when there is a position to lose: opening a note that was
  /// never started and changing a word should not interrupt with a question
  /// about progress that does not exist.
  Future<bool?> _confirmReset() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reset your progress?'),
      content: const Text(
        'Changing the text means your saved place in this note may no '
        'longer line up with it. Saving will start it over from the '
        'beginning.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Save and reset'),
        ),
      ],
    ),
  );

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _bodyController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit note' : 'Write a note'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              enabled: !_busy,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Untitled note',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _bodyController,
                enabled: !_busy,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Write what you want to read',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: (hasText && !_busy) ? _save : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save and read'),
            ),
          ],
        ),
      ),
    );
  }
}
