# epub_reader

EPUB parsing for hereader: turns a book file into normalized text blocks the
RSVP engine can read.

Pure Dart, no Flutter dependency.

## Scope

An EPUB is a zip of XHTML documents. This package unpacks it, follows the
spine, and reduces each document to plain readable text split into blocks.

It deliberately does not render, style, or preserve layout. Text that only
makes sense as layout, such as tables and figures, is dropped rather than
flattened into a stream of words.

## Usage

```dart
import 'package:epub_reader/epub_reader.dart';

final blocks = const HtmlNormalizer().normalize(
  xhtmlSource,
  href: 'OEBPS/chapter1.xhtml',
);

for (final block in blocks) {
  print('${block.kind}: ${block.text}');
}
```

## Blocks

A spine document becomes many blocks rather than one chapter, so a lost
reading position costs a paragraph rather than a chapter.

`Block.id` derives from the spine href and the block's position within that
document, never from its content. Two identical paragraphs would collide under
a content hash, and correcting a typo would move the reader's saved position.

`Block.text` is normalized: whitespace collapsed to single spaces, inline
markup flattened, entities decoded. Character offsets in a stored locator
index into this text, never into the source markup, which is why changing
normalization means bumping `kParserVersion`. See
[ADR 0002](../../docs/adr/0002-locator-format.md).

## What is dropped

Scripts, styles, tables, images, figures, MathML, and EPUB 3 navigation
documents. Blocks shorter than two characters go too, which clears page
numbers and paragraphs used as spacing.

## Testing

```bash
dart test
```

The normalizer is pure, so it tests against XHTML string literals rather than
fixture books. Container parsing, once built, will need real EPUBs.

## Status

Built: `Block`, `HtmlNormalizer`.

Not yet built: zip container reading, OPF manifest and spine parsing, metadata
extraction.
