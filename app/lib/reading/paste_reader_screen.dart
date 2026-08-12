import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import 'library_book.dart';
import 'reader_screen.dart';

/// Paste any text and read it. Kept permanently, not scaffolding: it is the
/// quickest way to try the engine against arbitrary text, including languages
/// the tokenizer has not been tuned for.
class PasteReaderScreen extends StatefulWidget {
  /// Threaded through to the reader rather than left out.
  ///
  /// Nothing here touches storage, but the reading surface does: a reader who
  /// needs 48pt light-on-dark needs it for pasted text too, and the profile
  /// they pick mid-read should be remembered like any other.
  final LibraryRepository repository;
  final Future<String> Function() issueStamp;

  const PasteReaderScreen({
    super.key,
    required this.repository,
    required this.issueStamp,
  });

  @override
  State<PasteReaderScreen> createState() => _PasteReaderScreenState();
}

class _PasteReaderScreenState extends State<PasteReaderScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    // One block, and parserVersion 0: this text came from the clipboard, not
    // from a parsed book, so its offsets belong to no normalizer version.
    final text = TokenizedText.from([
      (id: 'pasted', text: _controller.text),
    ], parserVersion: 0);

    if (text.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          book: LibraryBook(id: 'pasted', title: 'Pasted text', text: text),
          repository: widget.repository,
          issueStamp: widget.issueStamp,
          // Nothing to save to. Pasted text has no book row, so a position
          // against it would fail the foreign key, and a place in text that
          // exists only in this session is not worth syncing anyway. Stated
          // here rather than by discarding a value the screen returned,
          // which is how the same fact used to be expressed.
          onSave: (_) async {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Paste text')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Paste a chapter here',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: hasText ? _start : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              child: const Text('Read this'),
            ),
          ],
        ),
      ),
    );
  }
}
