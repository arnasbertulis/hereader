import 'dart:io';

import 'package:epub_reader/epub_reader.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    print('usage: dart run tool/dump_epub.dart <path to .epub>');
    exit(64);
  }

  final bytes = File(args.first).readAsBytesSync();
  final stopwatch = Stopwatch()..start();

  final EpubBook book;
  try {
    book = const EpubParser().parse(bytes);
  } on EpubException catch (e) {
    print('Failed: ${e.message}');
    exit(1);
  }
  stopwatch.stop();

  print('Title      ${book.metadata.title}');
  print('Author     ${book.metadata.author ?? "(none)"}');
  print('Language   ${book.metadata.language ?? "(none)"}');
  print('Cover      ${book.metadata.coverHref ?? "(none)"}');
  print('Documents  ${book.documents.length}');
  print('Blocks     ${book.blockCount}');
  print('Parsed in  ${stopwatch.elapsedMilliseconds} ms');
  print('');

  for (final block in book.readingOrder.take(12)) {
    final text = block.text.length > 90
        ? '${block.text.substring(0, 90)}...'
        : block.text;
    print('[${block.kind.name}] $text');
  }

  final chars = book.readingOrder.fold<int>(0, (sum, b) => sum + b.text.length);
  print('');
  print('Total characters: $chars');
}
