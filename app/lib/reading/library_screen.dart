import 'package:epub_reader/epub_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'library_book.dart';
import 'reader_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _books = <LibraryBook>[];
  bool _importing = false;

  Future<void> _import() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
      withData: true,
    );

    final bytes = result?.files.singleOrNull?.bytes;
    if (bytes == null || !mounted) return;

    setState(() => _importing = true);

    try {
      final book = await const BookImporter().import(bytes);
      if (!mounted) return;

      setState(() {
        _books.removeWhere((b) => b.id == book.id);
        _books.insert(0, book);
      });
    } on EpubException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _open(LibraryBook book) async {
    final position = await Navigator.of(context).push<Locator?>(
      MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
    );

    if (position == null || !mounted) return;

    setState(() {
      final i = _books.indexWhere((b) => b.id == book.id);
      if (i != -1) _books[i] = _books[i].withPosition(position);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            onPressed: _importing ? null : _import,
            icon: const Icon(Icons.add),
            tooltip: 'Add a book',
          ),
        ],
      ),
      body: _importing
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
          ? _EmptyLibrary(onImport: _import)
          : ListView.separated(
              itemCount: _books.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) =>
                  _BookTile(book: _books[i], onTap: () => _open(_books[i])),
            ),
    );
  }
}

class _BookTile extends StatelessWidget {
  final LibraryBook book;
  final VoidCallback onTap;

  const _BookTile({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final started = book.position != null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(book.title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (book.author != null) Text(book.author!),
          const SizedBox(height: 6),
          Text(
            started
                ? '${(book.progress * 100).round()}% through'
                : '${book.text.length} words',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (started) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: book.progress),
          ],
        ],
      ),
      trailing: Icon(started ? Icons.play_arrow : Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final VoidCallback onImport;

  const _EmptyLibrary({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No books yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Add an EPUB to start reading. Books stay on this device.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onImport,
              style: FilledButton.styleFrom(minimumSize: const Size(200, 56)),
              icon: const Icon(Icons.add),
              label: const Text('Add a book'),
            ),
          ],
        ),
      ),
    );
  }
}
