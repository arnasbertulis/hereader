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

final book = const EpubParser().parse(bytes);

print(book.metadata.title);
print(book.metadata.author);

for (final block in book.readingOrder) {
  print('${block.kind}: ${block.text}');
}
```

Bytes rather than a path: on the web there is no file behind a picker, and the
app stores bytes anyway.

Parsing is synchronous and CPU-bound — a few hundred milliseconds for a novel
— so callers should run it off the UI isolate.

Every failure surfaces as `EpubException` with a message fit to show a reader.
A missing or unreadable spine document is skipped rather than failing the
whole book, on the grounds that one broken chapter should not make a book
unopenable.

The normalizer can also be used directly on a single document, which is how it
is tested:

```dart
final blocks = const HtmlNormalizer().normalize(
  xhtmlSource,
  href: 'OEBPS/chapter1.xhtml',
);
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

## Front matter

`findContentStart` reports where a book's own text appears to begin, so a
reader does not open on a licence page.

Nothing is removed. Front matter keeps its place in the block list with its
ids intact, so saved positions are unaffected and a reader can rewind into it.

Two mechanisms of different quality, and the distinction matters. Project
Gutenberg writes an explicit start marker into every book it produces; that is
a documented delimiter, not a guess, and it wins outright. Failing that,
leading blocks matching catalogue prefixes or short rights lines are skipped —
a genuine guess, capped at fifteen percent of the book, and reported as
`ContentStartReason.boilerplateHeuristic` so a caller can offer a way back.

## What is dropped

Scripts, styles, tables, images, figures, MathML, and EPUB 3 navigation
documents. Blocks shorter than two characters go too, which clears page
numbers and paragraphs used as spacing.

Spine items that are not markup, such as SVG cover wrappers, are skipped.

## Testing

```bash
dart test
```

The normalizer and front matter detection are pure, so they test against
string literals. The container parser is tested against EPUBs built in memory
with `ZipEncoder`, which keeps those cases deterministic without committing
binaries.

`test/fixtures/` holds one real Project Gutenberg book. Synthetic fixtures
only confirm the assumptions this package already makes; that one was written
by someone else's toolchain, and its asserted block and character counts are
observed output. If a normalizer change moves them, that is a real change to
stored reading positions: update the numbers and bump `kParserVersion` in the
same commit.

## Status

Built: `Block`, `HtmlNormalizer`, `EpubParser`, front matter detection.

Not yet built: reading a book's own table of contents for chapter navigation,
and using the OPF language tag to select a per-language tokenizer
configuration.
